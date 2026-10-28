# Atualiz.IA

App pessoal (PWA para iPhone) para ler todo dia as matérias mais recentes sobre semiótica, design, comunicação, criatividade e publicidade, com meta diária de leitura.

**Abrir:** https://oiyuriv.github.io/atualizia/ no Safari → Compartilhar → *Adicionar à Tela de Início*.

## Como funciona

- `tools/sources.json`: as fontes (revistas, blogs, jornais e revistas acadêmicas do Brasil e de fora). Para incluir ou tirar uma fonte, é só editar esta lista.
- `tools/build-feed.ps1`: busca os feeds, traduz títulos e resumos de fora para o português, marca os temas e grava `data/feed.json`.
- `.github/workflows/feed.yml`: roda o coletor (matérias e eventos) a cada 2 horas no GitHub Actions e publica o site.
- `tools/events.json` + `tools/build-events.ps1`: a agenda da aba **Eventos** (congressos, chamadas de artigos, editais, palestras, cursos e prêmios da área). Junta feeds da UFPB, UECE, Compós, Socine, Abrapcorp e revistas com buscas no Google Notícias, lê no texto de cada notícia as datas, o prazo, o valor, as vagas, o que é pedido (artigo, prova, projeto…) e os links de inscrição, e grava `data/events.json`. Para as notícias do Google Notícias, a matéria original é achada pelo título no Bing Notícias. João Pessoa/Paraíba e Fortaleza/Ceará são prioridade, e edital de mestrado da área na UFPB ganha destaque. O `build-feed.ps1` chama esse arquivo; para rodar só a agenda: `powershell -File tools/build-feed.ps1 -EventsOnly`.
- `index.html`: o app inteiro. Notas, salvos, metas, a agenda guardada e o que o feed aprendeu ficam só no aparelho (localStorage).

Para testar no Windows: `powershell -File tools/build-feed.ps1` e depois `powershell -File serve.ps1` (porta 8802).
