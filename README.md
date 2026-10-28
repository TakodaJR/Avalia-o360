# Rede 360

Avaliação 360 com montagem de rede (convites com aprovação do gestor), avaliação por
pares, líder e rede, plano de sucessão e painel do RH.

> **Status: beta de demonstração.** Esta versão roda inteira no navegador, com dados
> de exemplo salvos só no navegador de quem abre. A ligação com o Supabase (login real
> e dados compartilhados) é a próxima etapa.

## Estrutura

| Arquivo | O que é |
|---|---|
| `index.html` | O app inteiro (telas, regras e dados de exemplo) |
| `favicon.png` | Ícone do Rede 360 |
| `supabase/schema.sql` | Estrutura do banco, regras de acesso e perguntas da avaliação (já aplicada no projeto `rede360-teste`) |

## Publicar na Vercel

1. Vercel → **Add New → Project** → importe este repositório.
2. **Framework Preset:** `Other`. Não precisa de comando de build.
3. **Deploy**. A cada novo commit na branch principal, a Vercel publica de novo sozinha.

## Testar a demonstração

No topo da página, use **"Ver como"** para trocar de pessoa:

- **Ana Souza** — colaboradora: monta a rede, avalia, vê o próprio perfil.
- **Ricardo Alves** — líder: aprova convites da equipe (inclusive em massa) e vê *Minha equipe*.
- **Camila Rocha** — RH: etapas do ciclo, pares e líderes, colaboradores, sucessão e resultados.

"Restaurar dados" (Visão geral do RH) volta tudo ao início.

## Regras principais

- Convites: quem envia escolhe **Cliente** ou **Fornecedor**; o **líder de quem envia** aprova; a pessoa convidada aceita ou recusa (recusa exige motivo).
- Avaliação: 5 critérios (Resiliência, Criatividade, Proatividade, Colaboração, Empatia), perguntas conforme o **cargo de quem é avaliado**, notas de **0 a 10** ou **Em branco** (fora das médias), comentário final obrigatório.
- Anonimato: a pessoa só vê médias, e cada grupo só aparece com 2 respostas ou mais (a nota do líder é a exceção).
- Sucessão: Sucessor Emergencial, Sucessor Imediato e Sucessor Em Preparação, com várias pessoas por grau. Visível só para o RH e para o líder da pessoa.
