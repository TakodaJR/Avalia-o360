-- =====================================================================
-- Rede 360 · estrutura do banco no Supabase
-- Só entra quem o RH cadastrou antes: o login é ligado ao cadastro pelo e-mail.
-- =====================================================================

-- ---------- Tabelas ----------
create table public.matrizes (
  id          uuid primary key default gen_random_uuid(),
  nome        text not null unique,
  lider_id    uuid,                       -- FK adicionada depois de profiles
  criado_em   timestamptz not null default now()
);

create table public.profiles (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid unique references auth.users(id) on delete set null,  -- preenchido no primeiro login
  nome        text not null,
  email       text not null unique check (email = lower(email)),
  papel       text not null default 'colab' check (papel in ('colab','admin')),
  matriz_id   uuid references public.matrizes(id) on delete set null,
  cargo       text not null default 'analista'
              check (cargo in ('auxiliar','analista','especialista','lideranca')),  -- define as perguntas da avaliação
  foto_url    text,
  criado_em   timestamptz not null default now()
);

alter table public.matrizes
  add constraint matrizes_lider_fk foreign key (lider_id)
  references public.profiles(id) on delete set null;

-- Ciclo e etapa atual (uma linha por ciclo; só um ativo)
create table public.ciclos (
  id          uuid primary key default gen_random_uuid(),
  nome        text not null,
  etapa       text not null default 'rede' check (etapa in ('rede','avaliacao','encerrado')),
  rede_inicio date not null default current_date,   -- início do período de montagem da rede
  rede_dias   int  not null default 40 check (rede_dias between 1 and 120),
  teste_avaliacao boolean not null default false,   -- libera a avaliação antes da etapa 2 (só para testes)
  ativo       boolean not null default true,
  criado_em   timestamptz not null default now()
);
create unique index um_ciclo_ativo on public.ciclos (ativo) where ativo;

create table public.convites (
  id          uuid primary key default gen_random_uuid(),
  ciclo_id    uuid not null references public.ciclos(id) on delete cascade,
  de_id       uuid not null references public.profiles(id) on delete cascade,
  para_id     uuid not null references public.profiles(id) on delete cascade,
  -- Fluxo: aguardando_gestor -> pendente (gestor aprovou) -> aceito / recusado
  --        aguardando_gestor -> reprovado (gestor não aprovou)
  status      text not null default 'aguardando_gestor'
              check (status in ('aguardando_gestor','pendente','aceito','recusado','reprovado','expirado')),
  -- o que a pessoa convidada é para quem convidou; para quem recebe, o papel se inverte
  relacao     text not null check (relacao in ('cliente','fornecedor')),
  aprovador_id uuid references public.profiles(id) on delete set null,  -- líder de quem envia
  aprovado_em timestamptz,
  respondido_em timestamptz,
  -- motivo informado por quem recusa; "outro" exige descrição
  motivo_recusa text check (motivo_recusa in ('nao_trabalho','relacao','sem_condicoes','outro')),
  motivo_detalhe text check (char_length(motivo_detalhe) <= 300),
  constraint recusa_com_motivo check (status <> 'recusado' or (motivo_recusa is not null
    and (motivo_recusa <> 'outro' or char_length(btrim(coalesce(motivo_detalhe,''))) >= 5))),
  visto_remetente boolean not null default false,   -- notificação de resposta já vista por quem convidou
  criado_em   timestamptz not null default now(),
  check (de_id <> para_id)
);
-- Um convite ativo por par de pessoas por ciclo, em qualquer direção
-- (depois de recusado ou reprovado, dá para convidar de novo)
create unique index convite_par_unico on public.convites
  (ciclo_id, least(de_id, para_id), greatest(de_id, para_id))
  where status not in ('recusado','reprovado','expirado');

create table public.avaliacoes (
  id          uuid primary key default gen_random_uuid(),
  ciclo_id    uuid not null references public.ciclos(id) on delete cascade,
  avaliador_id uuid not null references public.profiles(id) on delete cascade,
  avaliado_id uuid not null references public.profiles(id) on delete cascade,
  tipo        text not null check (tipo in ('rede','matriz','lider','equipe')),
  cargo_avaliado text not null,          -- cargo de quem foi avaliado no momento da resposta
  notas       jsonb not null,             -- {"res":8,"cri":10,"pro":null,"col":7,"emp":9}
  comentarios_criterio jsonb not null default '{}'::jsonb,  -- opcionais, por critério
  comentario  text not null check (char_length(btrim(comentario)) >= 20),  -- comentário final obrigatório
  enviado_em  timestamptz not null default now(),
  unique (ciclo_id, avaliador_id, avaliado_id),
  check (notas ?& array['res','cri','pro','col','emp']),
  -- cada critério: inteiro de 0 a 10, ou null ("Em branco", fica fora das médias)
  constraint avaliacoes_notas_0a10 check (not jsonb_path_exists(notas,
    '$.* ? (@.type() != "null" && (@.type() != "number" || @ < 0 || @ > 10 || @.floor() != @))')),
  check (avaliador_id <> avaliado_id)
);

-- Plano de sucessão: várias pessoas por grau, uma linha por pessoa.
-- 1 = Sucessor Emergencial, 2 = Sucessor Imediato, 3 = Sucessor Em Preparação.
-- A mesma pessoa aparece no máximo uma vez por líder (num único grau).
create table public.sucessao (
  lider_id   uuid not null references public.profiles(id) on delete cascade,
  pessoa_id  uuid not null references public.profiles(id) on delete cascade,
  grau       int  not null check (grau in (1,2,3)),
  criado_em  timestamptz not null default now(),
  primary key (lider_id, pessoa_id),
  check (lider_id <> pessoa_id)
);
create index sucessao_pessoa on public.sucessao(pessoa_id);

-- Perguntas da avaliação: 5 critérios x 4 cargos (o RH pode editar os textos)
create table public.perguntas (
  cargo     text not null check (cargo in ('auxiliar','analista','especialista','lideranca')),
  criterio  text not null check (criterio in ('res','cri','pro','col','emp')),
  nivel     int  not null,
  titulo    text not null,
  texto     text not null,
  primary key (cargo, criterio)
);
insert into public.perguntas (cargo, criterio, nivel, titulo, texto) values
 ('especialista','res',5,'Resiliência','Enfrenta desafios técnicos e organizacionais com equilíbrio e perseverança, mantendo qualidade e consistência mesmo sob pressão ou em cenários de incerteza.'),
 ('especialista','cri',4,'Criatividade','Desenvolve soluções técnicas inovadoras para desafios complexos, aplicando raciocínio analítico e criatividade prática para gerar avanços consistentes.'),
 ('especialista','pro',3,'Proatividade','Antecipa-se a riscos e oportunidades em sua área de atuação, propondo melhorias e implementando soluções de forma responsável e orientada a resultados.'),
 ('especialista','col',2,'Colaboração','Atua como referência em sua área de expertise, compartilhando conhecimento com clareza, contribuindo para decisões coletivas e promovendo um ambiente inclusivo e de aprendizado.'),
 ('especialista','emp',1,'Empatia','Compreende profundamente as necessidades do cliente e dos colegas, utilizando sua escuta ativa e conhecimento técnico para oferecer soluções adequadas e de alto impacto.'),
 ('auxiliar','res',5,'Resiliência','Mantém o foco nas tarefas mesmo diante de dificuldades, demonstrando responsabilidade com prazos e disposição para aprender.'),
 ('auxiliar','cri',4,'Criatividade','Dá sugestões simples para facilitar o trabalho e aceita mudanças com abertura, ajudando o time a se adaptar.'),
 ('auxiliar','pro',3,'Proatividade','Cumpre suas tarefas com atenção e responsabilidade, buscando apoio quando identifica problemas e contribuindo para manter a organização do trabalho.'),
 ('auxiliar','col',2,'Colaboração','Relaciona-se bem com colegas de diferentes áreas e perfis, mostrando respeito e disposição para colaborar no dia a dia.'),
 ('auxiliar','emp',1,'Empatia','Atua com atenção e cortesia, ouvindo com cuidado e buscando entender as necessidades do cliente para realizar suas atividades alinhadas às expectativas.'),
 ('analista','res',5,'Resiliência','Mantém o foco e o comprometimento mesmo diante de desafios, demonstrando persistência e equilíbrio em situações de pressão.'),
 ('analista','cri',4,'Criatividade','Sugere ideias e soluções práticas para melhorar processos ou resolver problemas, contribuindo com uma abordagem ágil e colaborativa.'),
 ('analista','pro',3,'Proatividade','Identifica problemas no dia a dia e propõe soluções, agindo com responsabilidade e comprometimento com os resultados do time.'),
 ('analista','col',2,'Colaboração','Colabora de forma aberta com colegas de diferentes origens e pontos de vista, respeitando as diferenças e contribuindo para um ambiente de trabalho inclusivo.'),
 ('analista','emp',1,'Empatia','Demonstra interesse genuíno pelas necessidades do cliente, ouvindo com atenção e buscando entender seus desafios para apoiar na construção de soluções adequadas.'),
 ('lideranca','res',5,'Resiliência','Persiste diante de desafios, mantendo o foco e o comprometimento mesmo em situações de pressão ou dificuldades.'),
 ('lideranca','cri',4,'Criatividade','Imagina soluções inovadoras para problemas complexos e desafiadores, mantendo uma abordagem prática e ágil para sua implementação.'),
 ('lideranca','pro',3,'Proatividade','Antecipa problemas e toma iniciativas para solucioná-los, agindo como se o sucesso do negócio dependesse diretamente de suas ações.'),
 ('lideranca','col',2,'Colaboração','Trabalha de forma aberta com pessoas de diferentes origens e perspectivas, incentiva ideias diversas e contribui para um ambiente inclusivo.'),
 ('lideranca','emp',1,'Empatia','Demonstra genuíno interesse pelas necessidades do cliente, ouve ativamente e busca compreender seus desafios antes de propor soluções.');

-- ---------- Funções auxiliares ----------
-- Cadastro (profiles.id) de quem está logado
create or replace function public.meu_id() returns uuid
language sql stable security definer set search_path = public as $$
  select id from profiles where user_id = auth.uid();
$$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where user_id = auth.uid() and papel = 'admin');
$$;

-- Avaliação aberta: etapa 2, ou modo de teste ligado (fora do ciclo encerrado)
create or replace function public.avaliacao_aberta() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from ciclos where ativo and (etapa = 'avaliacao' or (teste_avaliacao and etapa <> 'encerrado')));
$$;

create or replace function public.etapa_atual() returns text
language sql stable security definer set search_path = public as $$
  select etapa from ciclos where ativo limit 1;
$$;

-- Convites só valem na etapa "rede" e dentro do período (padrão de 40 dias)
create or replace function public.rede_aberta() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from ciclos where ativo and etapa = 'rede'
                 and current_date between rede_inicio and rede_inicio + (rede_dias - 1));
$$;

create or replace function public.ciclo_atual() returns uuid
language sql stable security definer set search_path = public as $$
  select id from ciclos where ativo limit 1;
$$;

-- Tipo de relação entre avaliador e avaliado (null = não pode avaliar)
create or replace function public.tipo_relacao(avaliador uuid, avaliado uuid) returns text
language sql stable security definer set search_path = public as $$
  with a as (select * from profiles where id = avaliador),
       b as (select * from profiles where id = avaliado)
  select case
    when exists (select 1 from a join matrizes m on m.id = a.matriz_id where m.lider_id = avaliado) then 'lider'
    when exists (select 1 from b join matrizes m on m.id = b.matriz_id where m.lider_id = avaliador) then 'equipe'
    when exists (select 1 from a, b where a.matriz_id is not null and a.matriz_id = b.matriz_id) then 'matriz'
    when exists (select 1 from convites c where c.ciclo_id = ciclo_atual() and c.status = 'aceito'
                 and ((c.de_id = avaliador and c.para_id = avaliado) or (c.de_id = avaliado and c.para_id = avaliador))) then 'rede'
  end;
$$;

-- No primeiro login, liga a conta ao cadastro feito pelo RH (pelo e-mail).
-- E-mail que não está cadastrado não consegue entrar.
create or replace function public.novo_usuario() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update profiles set user_id = new.id where email = lower(new.email) and user_id is null;
  if not found then
    raise exception 'E-mail % não está cadastrado no Rede 360. Fale com o RH.', new.email;
  end if;
  return new;
end $$;
create trigger ao_criar_usuario after insert on auth.users
  for each row execute function public.novo_usuario();

-- ---------- Regras de acesso (RLS) ----------
alter table public.profiles   enable row level security;
alter table public.matrizes   enable row level security;
alter table public.ciclos     enable row level security;
alter table public.convites   enable row level security;
alter table public.avaliacoes enable row level security;
alter table public.perguntas  enable row level security;
create policy perguntas_ler on perguntas for select to authenticated using (true);
create policy perguntas_admin on perguntas for all to authenticated using (is_admin()) with check (is_admin());

-- Perfis: todos os logados veem nomes/fotos; cada um edita só nome e foto; admin edita tudo
create policy perfis_ler on profiles for select to authenticated using (true);
create policy perfis_editar_proprio on profiles for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy perfis_admin on profiles for all to authenticated using (is_admin()) with check (is_admin());
-- Quem não é RH só muda nome e foto
create or replace function public.proteger_perfil() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- só vale para quem usa o app; limpezas automáticas do banco passam
  if current_setting('role', true) = 'authenticated' and not is_admin() and (new.email is distinct from old.email or new.papel is distinct from old.papel
     or new.matriz_id is distinct from old.matriz_id or new.cargo is distinct from old.cargo
     or new.user_id is distinct from old.user_id) then
    raise exception 'Só o RH pode alterar e-mail, papel, matriz ou cargo.';
  end if;
  return new;
end $$;
create trigger perfil_protegido before update on public.profiles
  for each row execute function public.proteger_perfil();

-- Matrizes e ciclos: todos leem, só admin altera
create policy matrizes_ler  on matrizes for select to authenticated using (true);
create policy matrizes_admin on matrizes for all to authenticated using (is_admin()) with check (is_admin());
create policy ciclos_ler    on ciclos for select to authenticated using (true);
create policy ciclos_admin on ciclos for all to authenticated using (is_admin()) with check (is_admin());

-- Sucessão: dado sensível, somente o RH lê e altera
alter table public.sucessao enable row level security;
create policy sucessao_admin on sucessao for all to authenticated using (is_admin()) with check (is_admin());

-- Ao criar um convite, o servidor define como aprovador o líder de QUEM ENVIA.
-- Se quem envia não tem líder, ou se o líder é a própria pessoa convidada, vai direto para "pendente".
create or replace function public.definir_aprovador() returns trigger
language plpgsql security definer set search_path = public as $$
declare g uuid;
begin
  select m.lider_id into g from profiles p join matrizes m on m.id = p.matriz_id where p.id = new.de_id;
  if g is null or g = new.de_id or g = new.para_id then
    new.aprovador_id := null; new.status := 'pendente'; new.aprovado_em := now();
  else
    new.aprovador_id := g; new.status := 'aguardando_gestor';
  end if;
  return new;
end $$;
create trigger convite_aprovador before insert on public.convites
  for each row execute function public.definir_aprovador();

-- Convites: quem convida e o gestor veem sempre; quem recebe só vê depois da aprovação
create policy convites_ler on convites for select to authenticated
  using (de_id = meu_id() or aprovador_id = meu_id() or is_admin()
         or (para_id = meu_id() and status <> 'aguardando_gestor'));
create policy convites_enviar on convites for insert to authenticated
  with check (de_id = meu_id() and rede_aberta() and ciclo_id = ciclo_atual());
-- Gestor aprova ou não aprova
create policy convites_gestor on convites for update to authenticated
  using (aprovador_id = meu_id() and status = 'aguardando_gestor' and rede_aberta())
  with check (aprovador_id = meu_id() and status in ('pendente','reprovado'));
-- Quem recebe aceita ou recusa, só depois da aprovação
create policy convites_responder on convites for update to authenticated
  using (para_id = meu_id() and status = 'pendente' and rede_aberta())
  with check (para_id = meu_id() and status in ('aceito','recusado'));
-- Marca como vistas as respostas aos convites que eu enviei
create or replace function public.marcar_notificacoes_vistas() returns void
language sql security definer set search_path = public as $$
  update convites set visto_remetente = true
  where de_id = meu_id() and status in ('aceito','recusado','reprovado') and not visto_remetente;
$$;
-- Registra a hora da aprovação e da resposta
create or replace function public.carimbar_convite() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.status = 'pendente' and old.status = 'aguardando_gestor' then new.aprovado_em := now(); end if;
  if new.status in ('aceito','recusado','reprovado') and old.status is distinct from new.status then
    new.respondido_em := now(); new.visto_remetente := false;
  end if;
  return new;
end $$;
create trigger convite_carimbo before update on public.convites
  for each row execute function public.carimbar_convite();
-- A relação cliente/fornecedor não muda depois do envio
create or replace function public.travar_relacao() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.relacao is distinct from old.relacao then
    raise exception 'A relação cliente/fornecedor não pode ser alterada depois do envio.';
  end if;
  return new;
end $$;
create trigger convite_relacao_fixa before update on public.convites
  for each row execute function public.travar_relacao();
create policy convites_cancelar on convites for delete to authenticated
  using (de_id = meu_id() and status in ('aguardando_gestor','pendente') and rede_aberta());

-- Avaliações: ninguém lê respostas individuais de outros (só o próprio avaliador e o admin)
create policy aval_ler_proprias on avaliacoes for select to authenticated
  using (avaliador_id = meu_id() or is_admin());
create policy aval_enviar on avaliacoes for insert to authenticated
  with check (avaliador_id = meu_id() and avaliacao_aberta() and ciclo_id = ciclo_atual()
              and tipo = tipo_relacao(meu_id(), avaliado_id));
create policy aval_editar on avaliacoes for update to authenticated
  using (avaliador_id = meu_id() and avaliacao_aberta())
  with check (avaliador_id = meu_id() and tipo = tipo_relacao(meu_id(), avaliado_id));
-- O cargo usado nas perguntas é sempre o cargo atual de quem é avaliado
create or replace function public.carimbar_cargo() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  select cargo into new.cargo_avaliado from profiles where id = new.avaliado_id;
  new.enviado_em := now();
  return new;
end $$;
create trigger avaliacao_cargo before insert or update on public.avaliacoes
  for each row execute function public.carimbar_cargo();

-- ---------- Resultados (sempre agregados, nunca respostas individuais) ----------
-- Quem pode ver o resultado de uma pessoa: ela mesma, o líder da matriz dela, ou o RH
create or replace function public.pode_ver_resultado(pessoa uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select is_admin() or pessoa = meu_id()
      or exists (select 1 from profiles p join matrizes m on m.id = p.matriz_id
                 where p.id = pessoa and m.lider_id = meu_id());
$$;

-- Médias por critério de uma pessoa. Para a própria pessoa, grupos com menos de 2
-- respostas ficam de fora (anonimato); a nota do líder (tipo 'equipe') sempre conta.
create or replace function public.resultado_pessoa(pessoa uuid)
returns table (criterio text, media numeric, respostas int, ocultas int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not pode_ver_resultado(pessoa) then raise exception 'Sem permissão'; end if;
  return query
  with r as (select a.tipo, a.notas from avaliacoes a where a.avaliado_id = pessoa and a.ciclo_id = ciclo_atual()),
       g as (select r.tipo, count(*)::int n from r group by r.tipo),
       vis as (select r.* from r join g on g.tipo = r.tipo
               where pessoa is distinct from meu_id() or g.tipo = 'equipe' or g.n >= 2)
  select kv.key, round(avg(kv.value::numeric), 2),
         (select count(*)::int from vis), (select count(*)::int from r) - (select count(*)::int from vis)
  from vis cross join lateral jsonb_each_text(vis.notas) kv
  group by kv.key;
end $$;

-- Média de cada cargo por critério (sem contar a pessoa informada), para a comparação em %
create or replace function public.medias_cargo(exceto uuid default null)
returns table (cargo text, criterio text, media numeric, pessoas int)
language sql stable security definer set search_path = public as $$
  with por_pessoa as (
    select p.id, p.cargo, kv.key crit, avg(kv.value::numeric) m
    from avaliacoes a join profiles p on p.id = a.avaliado_id
    cross join lateral jsonb_each_text(a.notas) kv
    where a.ciclo_id = ciclo_atual() and p.id is distinct from exceto
    group by p.id, p.cargo, kv.key)
  select por_pessoa.cargo, crit, round(avg(m), 2), count(distinct id)::int from por_pessoa group by por_pessoa.cargo, crit;
$$;

-- Comentários recebidos, sem o nome de quem escreveu
create or replace function public.comentarios_pessoa(pessoa uuid)
returns table (geral text, por_criterio jsonb)
language plpgsql stable security definer set search_path = public as $$
begin
  if not pode_ver_resultado(pessoa) then raise exception 'Sem permissão'; end if;
  return query
  select a.comentario, a.comentarios_criterio from avaliacoes a
  where a.avaliado_id = pessoa and a.ciclo_id = ciclo_atual()
    and (pessoa is distinct from meu_id() or a.tipo = 'equipe' or (select count(*) from avaliacoes b
         where b.avaliado_id = a.avaliado_id and b.ciclo_id = a.ciclo_id and b.tipo = a.tipo) >= 2)
  order by random();
end $$;

-- Graus sucessórios das pessoas da minha equipe (para líderes) ou de todos (RH)
create or replace function public.sucessao_visivel()
returns table (pessoa uuid, lider uuid, grau int)
language sql stable security definer set search_path = public as $$
  select s.pessoa_id, s.lider_id, s.grau from sucessao s
  where is_admin() or exists (select 1 from profiles pr join matrizes m on m.id = pr.matriz_id
                              where pr.id = s.pessoa_id and m.lider_id = meu_id());
$$;

-- ---------- Fotos de perfil (Storage) ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 1048576, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

-- Cada pessoa grava só na própria pasta: avatars/<id do usuário>/foto.jpg
create policy avatar_ler on storage.objects for select to authenticated using (bucket_id = 'avatars');
create policy avatar_enviar on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy avatar_trocar on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy avatar_apagar on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------- Notificações em tempo real ----------
alter publication supabase_realtime add table public.convites;

-- ---------- Dados iniciais ----------
insert into public.ciclos (nome, etapa, teste_avaliacao) values ('Ciclo 2026 · teste', 'rede', true);
-- Primeiro administrador (RH)
insert into public.profiles (nome, email, papel, cargo)
values ('Joaquim Rabaço', 'joaquim.rabaco@takodadatacenters.com', 'admin', 'lideranca');

-- ---------- Permissões das funções ----------
-- Ninguém sem login executa funções do app
revoke execute on all functions in schema public from public, anon;
-- Funções de gatilho não são chamadas diretamente por ninguém
revoke execute on function public.novo_usuario(), public.proteger_perfil(), public.definir_aprovador(),
  public.carimbar_convite(), public.carimbar_cargo(), public.travar_relacao() from authenticated;
grant execute on function public.meu_id(), public.is_admin(), public.avaliacao_aberta(), public.etapa_atual(),
  public.rede_aberta(), public.ciclo_atual(), public.tipo_relacao(uuid, uuid), public.pode_ver_resultado(uuid),
  public.resultado_pessoa(uuid), public.medias_cargo(uuid), public.comentarios_pessoa(uuid),
  public.sucessao_visivel(), public.marcar_notificacoes_vistas() to authenticated;
alter default privileges in schema public revoke execute on functions from public, anon;
