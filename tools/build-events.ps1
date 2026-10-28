# Atualiz.IA: agenda de eventos da área (congressos, chamadas de artigos, editais, palestras, cursos) e grava data/events.json.
# Não roda sozinho: o build-feed.ps1 carrega este arquivo depois de definir as funções de rede, XML e texto.
# Prioridades: João Pessoa/Paraíba e Fortaleza/Ceará. Edital de mestrado da área na UFPB ganha destaque (m = 1).
#
# Campos de cada evento no events.json:
#   id  identificador   s  fonte (id em events.json; "gnews" = Google Notícias)   u  link   pub  veículo (Google Notícias)
#   t   título          d  resumo   at  data de publicação   fs  primeira vez que o coletor viu
#   k   tipo (congresso, chamada, edital, palestra, curso, premio, evento)
#   r   região (jp, ce, ne, online, br)   pl  cidade
#   w   data do evento (aaaa-mm-dd, ou aaaa-mm quando a notícia só diz o mês)   we  último dia
#   ds  início das inscrições ou submissões   dl  prazo (inscrição, submissão)
#   m   edital de mestrado ou doutorado da área em João Pessoa/UFPB
#   ru  link da matéria original (quando veio pelo Google Notícias)   dx  já procurou os detalhes
#   x   detalhes lidos do texto: val valor, pz prêmio, vag vagas, fmt presencial/online, loc local,
#       how como se inscrever, req o que é pedido (lista), lk links de inscrição/edital ({u, t}), ex resumo

$evCfg = Get-Content -Raw -Encoding UTF8 (Join-Path $here 'events.json') | ConvertFrom-Json
$evOut = Join-Path (Split-Path $Out) 'events.json'
$evNow = [DateTimeOffset]::UtcNow
$evNowIso = $evNow.ToString('o')
# o dia de hoje no horário de Fortaleza e João Pessoa
$evToday = $evNow.ToOffset([TimeSpan]::FromHours(-3)).Date

# ---------- regras ----------
$EvRx = { param($p) New-Object Text.RegularExpressions.Regex($p, $RegexOpts) }
# palavra da área: obrigatória para fontes gerais (universidades, Google Notícias)
$EvArea = & $EvRx ('comunica[çc]|jornalis|publicid|publicit|propaganda|marketing|\bdesign|semi[óo]ti|semiolog|\bm[íi]dias?\b|midi[áa]tic|cinema|audiovisual|fotogra|' +
  'rela[çc][õo]es p[úu]blicas|linguag|lingu[íi]stic|\bletras\b|an[áa]lise do discurso|narrativ|tipogra|branding|artes visuais|cultura digital|redes sociais|podcast|' +
  '\br[áa]dio\b|televis|streaming|ilustra[çc]|quadrinhos|\bPPGC\b|\bPPGJ\b|PPGCOM|intercom|comp[óo]s\b|socine|abrapcorp|sbpjor|expocom|desinforma|checagem|influenciad')
# notícia sobre o que já passou, resultado, carta, entrevista, luta do UFC...
$EvSkip = & $EvRx ('\banais\b|resultado|vencedor|recebe \d+ inscri|finalista|premiad|homolog|aprovad|nota p[úu]blica|carta aberta|carta em defesa|entrevista|\bjornal n[ºo°]|' +
  'faleceu|\bmorre|conclui|realizou|reuniu|encerrou|aconteceu|foi realizad|participou|participa\b|conquista|marca presen|marcou presen|amplia presen|com presen[çc]a d|[ée] apresentad|celebrou|' +
  'segundo turno|primeiro turno|debate (final|entre|presidencial|eleitoral)|' +
  '\bUFC\s?\d|\bUFC (Paris|Vegas|Fight)|oct[óo]gono|lutador|nocaute|pesagem|\bMMA\b')
# o primeiro tipo que bater no título vale; no resumo só vale tipo que não seja chamada ou "evento" solto
$EvKinds = @(
  @{ k = 'chamada'; rx = & $EvRx 'chamada|call for (papers|proposals)|submiss|recebem? (artigos|trabalhos|propostas|resumos)|dossi[êe]|envio de (artigos|trabalhos|resumos|propostas)' }
  @{ k = 'edital'; rx = & $EvRx '\bedita(l|is)\b|processo seletivo|sele[çc][ãa]o (para|de|do|da)|abre (sele[çc][ãa]o|vagas)|inscri[çc][õo]es (abertas )?para (o |a )?(mestrado|doutorado|especializa)|vagas (para|de|no|em) (mestrado|doutorado)' }
  @{ k = 'festival'; rx = & $EvRx 'festival|\bmostra\b|bienal' }
  @{ k = 'congresso'; rx = & $EvRx 'congresso|simp[óo]sio|semin[áa]rio|col[óo]quio|confer[êe]ncia|jornada|f[óo]rum|encontro|semana (de|da|do|acad)|expocom|intercom (nordeste|nacional|sudeste|sul|norte|centro)' }
  @{ k = 'palestra'; rx = & $EvRx 'palestra|mesa[- ]redonda|roda de conversa|aula (inaugural|aberta|magna|p[úu]blica)|\bdebate|lan[çc]amento d[eo] livro|bate-papo|\blive\b' }
  @{ k = 'curso'; rx = & $EvRx 'minicurso|oficinas?\b|workshop|masterclass|capacita[çc]|curso (de extens|livre|gratuito|online|on-line|de curta|de f[ée]rias|intensivo)|\bcursos?\b.{0,40}inscri|inscri.{0,40}\bcursos?\b' }
  @{ k = 'premio'; rx = & $EvRx '(pr[êe]mio|concurso).{0,60}(inscri|submiss|abre|recebe|concorr)|(inscri|submiss|abre|recebe).{0,60}(pr[êe]mio|concurso)' }
  @{ k = 'evento'; rx = & $EvRx '\beventos?\b|\bfeira\b|hackathon|meetup|summit' }
)
# "evento" sozinho só vale com cara de anúncio ("Fortaleza recebe evento...", não "evento mal desenhado")
$EvAnnounce = & $EvRx 'recebe|realiza|promove|acontece|sedia|\babre|chega|ter[áa]\b|ser[áa]\b|nesta|neste|pr[óo]xim|inscri|programa[çc]|vem a[íi]|anuncia|lan[çc]a|convida'
# a primeira região que bater vale (João Pessoa antes de Fortaleza, as duas antes do resto)
$EvRegions = @(
  @{ r = 'jp'; rx = & $EvRx 'Jo[ãa]o Pessoa|Para[íi]ba|paraiban|\bUFPB\b|\bIFPB\b|\bUEPB\b|\bUFCG\b|Unip[êe]|\bUniesp\b|Campina Grande|Cabedelo|\(PB\)|/PB\b' }
  @{ r = 'ce'; rx = & $EvRx 'Fortaleza|Cear[áa]|cearense|\bUFC\b|\bUECE\b|Unifor|\bIFCE\b|Unichristus|Uninta|\bUFCA\b|Sobral|Juazeiro do Norte|\bCrato\b|Cariri|Drag[ãa]o do Mar|Porto Iracema|\(CE\)|/CE\b' }
  @{ r = 'ne'; rx = & $EvRx 'Nordeste|nordestin|Recife|Pernambuco|\bUFPE\b|Unicap|Natal \(RN\)|Natal/RN|\bUFRN\b|Rio Grande do Norte|Salvador|Bahia|\bUFBA\b|Macei[óo]|Alagoas|\bUFAL\b|Teresina|Piau[íi]|\bUFPI\b|S[ãa]o Lu[íi]s|Maranh[ãa]o|\bUFMA\b|Aracaju|Sergipe' }
  @{ r = 'online'; rx = & $EvRx '\bonline\b|on-line|\bvirtual\b|remot[oa]\b|youtube|transmiss[ãa]o ao vivo' }
)
# quando o texto não diz o lugar, o veículo local entrega (Google Notícias)
$EvPubRegions = @(
  @{ r = 'jp'; rx = & $EvRx 'Jornal da Para[íi]ba|Portal Correio|Correio da Para[íi]ba|Pol[êe]mica Para[íi]ba|Campina FM|ClickPB|PB Agora|Para[íi]ba (dia a dia|J[áa])|WSCOM|MaisPB|\bMPPB\b|THMais|A Uni[ãa]o' }
  @{ r = 'ce'; rx = & $EvRx '\bO Povo\b|Di[áa]rio do Nordeste|GCMais|Jangadeiro|Verdes Mares|\bMPCE\b|Fecom[ée]rcio Cear|Sobral|Unifor|Cear[áa]' }
)
$EvCityRx = & $EvRx 'Jo[ãa]o Pessoa|Campina Grande|Cabedelo|Fortaleza|Sobral|Juazeiro do Norte|Crato|Recife|Salvador|Macei[óo]|Teresina|S[ãa]o Lu[íi]s|Aracaju'
$EvCities = @{ 'joao pessoa' = @('João Pessoa', 'jp'); 'campina grande' = @('Campina Grande', 'jp'); 'cabedelo' = @('Cabedelo', 'jp'); 'fortaleza' = @('Fortaleza', 'ce'); 'sobral' = @('Sobral', 'ce'); 'juazeiro do norte' = @('Juazeiro do Norte', 'ce'); 'crato' = @('Crato', 'ce'); 'recife' = @('Recife', 'ne'); 'salvador' = @('Salvador', 'ne'); 'maceio' = @('Maceió', 'ne'); 'teresina' = @('Teresina', 'ne'); 'sao luis' = @('São Luís', 'ne'); 'aracaju' = @('Aracaju', 'ne') }
$EvMest = @(
  (& $EvRx 'mestrado|doutorado|p[óo]s-gradua'),
  (& $EvRx 'edita(l|is)|sele[çc][ãa]o|seletivo|inscri[çc]|vagas|candidat')
)
$EvMestLocal = & $EvRx '\bUFPB\b|Jo[ãa]o Pessoa|Para[íi]ba|\bPPGC\b|\bPPGJ\b'

# ---------- datas ----------
$EvMonths = @{ janeiro = 1; fevereiro = 2; 'março' = 3; marco = 3; abril = 4; maio = 5; junho = 6; julho = 7; agosto = 8; setembro = 9; outubro = 10; novembro = 11; dezembro = 12 }
$EvMon = 'janeiro|fevereiro|mar[çc]o|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro'
$EvDateRx = & $EvRx ("(?<d1>\d{1,2})(?:º|°)?(?:\s*(?:a|e|-|–|ao)\s*(?<d2>\d{1,2})(?:º|°)?)?\s+de\s+(?<mo>$EvMon)(?:\s+de\s+(?<y>20\d\d))?" +
  '|(?<![\w/])(?<nd>\d{1,2})/(?<nm>\d{1,2})(?:/(?<ny>20\d\d|\d\d))?(?![\w/])' +
  '|(?:nesta|neste|nessa|nesse|na pr[óo]xima|no pr[óo]ximo|na|no)\s+(?:segunda|ter[çc]a|quarta|quinta|sexta|s[áa]bado|domingo)(?:-feira)?,?\s*\((?<wdd>\d{1,2})(?:º|°)?\)' +
  '|(?<wp>nesta|neste|nessa|nesse|na pr[óo]xima|no pr[óo]ximo)\s+(?<wd2>(?:segunda|ter[çc]a|quarta|quinta|sexta)-feira|s[áa]bado|domingo)\b(?!,?\s*\(\d)' +
  "|(?<om0>\bat[ée]|\bem|\bpara|no m[êe]s de)\s+(?<om>$EvMon)(?:\s+de\s+(?<oy>20\d\d))?")
# palavra de prazo logo antes da data, sem outro número no meio ("inscrições até o dia 30 de novembro")
$EvDlRx = & $EvRx '(at[ée]|prazo|encerra\w*|termina\w*|limite|prorroga\w*|[úu]ltimo dia)\b[^\d.;!?]*$'
# a data fala de inscrição ou submissão ("as inscrições serão de 21 a 30 de novembro")
$EvInscRx = & $EvRx '(inscri\w*|submiss\w*|candidatura\w*|envio d\w+|recebe\w* (artigos|trabalhos|propostas|resumos))\b[^\d.;!?]*$'
$EvStartRx = & $EvRx '(a partir d[eo]|come[çc]a\w*|abre\w*|in[íi]cio|abertura)\b[^\d.;!?]*$'

function Resolve-EvDate([int]$y, [int]$m, [int]$d, [DateTime]$pub) {
  if ($m -lt 1 -or $m -gt 12) { return $null }
  $yy = if ($y) { if ($y -lt 100) { 2000 + $y } else { $y } } else { $pub.Year }
  if ($d -eq 0) {
    # só o mês: se já acabou bem antes da notícia, é do ano seguinte
    $last = (New-Object DateTime $yy, $m, 1).AddMonths(1).AddDays(-1)
    if (-not $y -and $last -lt $pub.AddDays(-20)) { $yy++ }
    return New-Object DateTime $yy, $m, 1
  }
  if ($d -lt 1 -or $d -gt [DateTime]::DaysInMonth($yy, $m)) { return $null }
  $dt = New-Object DateTime $yy, $m, $d
  if (-not $y -and $dt -lt $pub.AddDays(-45)) { $dt = $dt.AddYears(1) }
  $dt
}

# w/we = quando o evento acontece; ds/dl = período de inscrição ou submissão (dl = prazo)
function Get-EvDates([string[]]$Texts, [DateTime]$Pub) {
  $w = $null; $we = $null; $ds = $null; $dl = $null; $window = $false
  $min = $Pub.AddDays(-45); $max = $Pub.AddMonths(18)
  foreach ($txt in $Texts) {
    if (-not $txt) { continue }
    foreach ($m in $EvDateRx.Matches($txt)) {
      $g = $m.Groups
      $y = 0; $mo = 0; $d1 = 0; $d2 = 0; $monthOnly = $false; $dlWord = $false
      if ($g['mo'].Success) {
        $mo = [int]$EvMonths[$g['mo'].Value.ToLowerInvariant()]; $d1 = [int]$g['d1'].Value
        if ($g['d2'].Success) { $d2 = [int]$g['d2'].Value }
        if ($g['y'].Success) { $y = [int]$g['y'].Value }
      } elseif ($g['nd'].Success) {
        $d1 = [int]$g['nd'].Value; $mo = [int]$g['nm'].Value
        if ($g['ny'].Success) { $y = [int]$g['ny'].Value }
      } elseif ($g['wdd'].Success) {
        # "nesta sexta (9)": o mês é o da notícia, ou o seguinte se o dia já passou
        $d1 = [int]$g['wdd'].Value; $mo = $Pub.Month
        if ($d1 -lt $Pub.Day - 3) { $mo++; if ($mo -gt 12) { $mo = 1; $y = $Pub.Year + 1 } }
      } elseif ($g['wd2'].Success) {
        # "no próximo domingo": o dia da semana seguinte à notícia
        $wd = @{ seg = 1; ter = 2; qua = 3; qui = 4; sex = 5; 'sáb' = 6; sab = 6; dom = 0 }[$g['wd2'].Value.Substring(0, 3).ToLowerInvariant()]
        $ahead = ($wd - [int]$Pub.DayOfWeek + 7) % 7
        if ($ahead -eq 0 -and $g['wp'].Value -match 'pr') { $ahead = 7 }
        $nd = $Pub.AddDays($ahead); $y = $nd.Year; $mo = $nd.Month; $d1 = $nd.Day
      } elseif ($g['om'].Success) {
        $mo = [int]$EvMonths[$g['om'].Value.ToLowerInvariant()]; $monthOnly = $true
        if ($g['oy'].Success) { $y = [int]$g['oy'].Value }
        $dlWord = $g['om0'].Value -match '^at'
      }
      $dt = Resolve-EvDate $y $mo $(if ($monthOnly) { 0 } else { $d1 }) $Pub
      if (-not $dt -or $dt -lt $min -or $dt -gt $max) { continue }
      $pre = $txt.Substring([Math]::Max(0, $m.Index - 60), [Math]::Min(60, $m.Index))
      $s = if ($monthOnly) { $dt.ToString('yyyy-MM') } else { $dt.ToString('yyyy-MM-dd') }
      $end = $null
      if ($d2 -gt $d1 -and $d2 -le [DateTime]::DaysInMonth($dt.Year, $dt.Month)) { $end = (New-Object DateTime $dt.Year, $dt.Month, $d2).ToString('yyyy-MM-dd') }
      $isDl = $dlWord -or $EvDlRx.IsMatch($pre)
      $isInsc = $EvInscRx.IsMatch($pre)
      if ($end -and ($isInsc -or $isDl)) {
        # período de inscrição vale mais que um "até" solto (isenção de taxa, por exemplo)
        if (-not $window) { $ds = $s; $dl = $end; $window = $true }
      } elseif ($isDl) {
        if (-not $dl) { $dl = $s }
      } elseif ($isInsc -and $EvStartRx.IsMatch($pre)) {
        if (-not $ds) { $ds = $s }
      } elseif (-not $w) {
        $w = $s; $we = $end
      }
      if ($w -and $dl -and $window) { break }
    }
    if ($w -and $dl -and $window) { break }
  }
  @{ w = $w; we = $we; ds = $ds; dl = $dl }
}

# último dia que ainda conta: "aaaa-mm" vale até o fim do mês
function Get-EvEnd([string]$s) {
  if (-not $s) { return $null }
  $p = $s.Split('-')
  if ($p.Count -lt 3) { return (New-Object DateTime ([int]$p[0]), ([int]$p[1]), 1).AddMonths(1).AddDays(-1) }
  New-Object DateTime ([int]$p[0]), ([int]$p[1]), ([int]$p[2])
}

# continua na agenda enquanto alguma data não passou; sem data, vale a janela da fonte
function Test-EvAlive($e, [DateTimeOffset]$At, [int]$Days) {
  $last = $null
  foreach ($v in @($e.we, $e.w, $e.dl, $e.ds)) {
    $d = Get-EvEnd $v
    if ($d -and (-not $last -or $d -gt $last)) { $last = $d }
  }
  if ($last) { return ($last -ge $evToday) -and ($At -gt $evNow.AddDays(-300)) }
  $At -gt $evNow.AddDays(-$Days)
}

# ---------- leitura ----------
function Read-EvNode($Node, $Src) {
  $it = Read-Item $Node $Src
  if (-not $it) { return $null }
  $pub = $null
  if ($Src.id -eq 'gnews') {
    # título vem como "Título - Veículo" e o resumo só repete o título
    $sn = $Node.SelectSingleNode("*[local-name()='source']")
    if ($null -ne $sn) { $pub = $sn.InnerText.Trim(); $site = $sn.GetAttribute('url') }
    if ($pub -and $it.t.EndsWith(" - $pub")) { $it.t = $it.t.Substring(0, $it.t.Length - $pub.Length - 3).Trim() }
    elseif ($it.t -match '^(.*\S)\s+-\s+([^-]{2,80})$') { $it.t = $Matches[1]; if (-not $pub) { $pub = $Matches[2].Trim() } }
    $it.d = ''
    return @{ it = $it; body = ''; html = ''; pub = $pub; site = $site }
  }
  # o texto inteiro dá as datas e os detalhes (valor, vagas, o que pede); avisos de revista vêm só na descrição
  $html = Get-Markup $Node $XP.content
  if (-not $html) { $html = Get-Markup $Node $XP.desc }
  @{ it = $it; body = (ConvertFrom-Html $html); html = $html; pub = $pub; site = $null }
}

function Get-EvInfo($It, $Src, [string]$Body, [DateTime]$Pub, [string]$Outlet) {
  $head = "$($It.t) $($It.d)"
  if ($EvSkip.IsMatch($It.t)) { return $null }
  $area = $Src.area -or $EvArea.IsMatch($head)
  if (-not $area) { return $null }
  $kind = $null
  foreach ($k in $EvKinds) {
    if ($k.rx.IsMatch($It.t) -and ($k.k -ne 'evento' -or $EvAnnounce.IsMatch($It.t))) { $kind = $k.k; break }
  }
  if (-not $kind -and $It.d) { foreach ($k in $EvKinds) { if ($k.k -ne 'chamada' -and $k.k -ne 'evento' -and $k.rx.IsMatch($It.d)) { $kind = $k.k; break } } }
  $mest = $kind -ne 'chamada' -and $EvMest[0].IsMatch($head) -and $EvMest[1].IsMatch($head) -and ($Src.region -eq 'jp' -or $EvMestLocal.IsMatch($head)) -and $EvArea.IsMatch($head)
  if ($mest) { $kind = 'edital' }
  if (-not $kind) { return $null }
  $region = $null
  foreach ($rr in $EvRegions) { if ($rr.rx.IsMatch($head)) { $region = $rr.r; break } }
  if (-not $region -and $Outlet) { foreach ($rr in @($EvPubRegions) + @($EvRegions[0..2])) { if ($rr.rx.IsMatch($Outlet)) { $region = $rr.r; break } } }
  if (-not $region) { $region = $(if ($Src.region) { $Src.region } else { 'br' }) }
  $city = $null
  foreach ($cm in $EvCityRx.Matches($head)) {
    $key = $cm.Value.ToLowerInvariant().Replace('ã', 'a').Replace('ó', 'o').Replace('í', 'i')
    $c = $EvCities[$key]
    if ($c -and $c[1] -eq $region) { $city = $c[0]; break }
  }
  $dates = Get-EvDates @($It.t, $It.d, (Get-Start $Body 2500)) $Pub
  @{ k = $kind; r = $region; pl = $city; w = $dates.w; we = $dates.we; ds = $dates.ds; dl = $dates.dl; m = $mest }
}
function Get-Start([string]$s, [int]$n) { if ($s.Length -gt $n) { $s.Substring(0, $n) } else { $s } }

# ---------- detalhes de inscrição ----------
# Do texto da notícia: valor, prêmio, vagas, presencial/online, local, o que é pedido, link de inscrição e um resumo.
$EvMoneyRx = & $EvRx 'R\$\s?\d{1,3}(?:\.\d{3})*(?:,\d{2})?(?:\s?mil\b)?'
$EvFeeCtx = & $EvRx '(inscri|taxa|valor|investimento|ingresso|custa|lote|pagamento|pre[çc]o|mensalidade|parcela)'
$EvPrizeCtx = & $EvRx '(pr[êe]mi|premia|bolsa|aux[íi]lio|recompensa)'
$EvFreeRx = & $EvRx 'gratuit[oa]s?\b|sem custo|entrada (franca|gratuita)|acesso (livre|gratuito)|sem taxa|n[ãa]o h[áa] (taxa|cobran)'
$EvExemptRx = & $EvRx 'isen[çc][ãa]o'
$EvSeatsRx = & $EvRx '(\d{1,4})\s+vagas'
$EvOnlineRx = & $EvRx '\bonline\b|on-line|remot[oa]\b|\bvirtual\b|a dist[âa]ncia|\bEaD\b|youtube|google meet|\bzoom\b'
$EvPresRx = & $EvRx 'presencia(l|is)\b|presencialmente'
$EvHybridRx = & $EvRx 'h[íi]brid[oa]'
$EvPlaceRx = & $EvRx '\b(?:no|na|nos|nas)\s+((?:audit[óo]rio|anfiteatro|centro de conven[çc][õo]es|centro cultural|centro de eventos|teatro|cineteatro|museu|biblioteca|pal[áa]cio|espa[çc]o|pr[ée]dio|bloco|sala|drag[ãa]o do mar|campus)\b[^.;:!?]{2,70})'
$EvHowRx = & $EvRx '(?:pelo|pela|no|na|atrav[ée]s d[oa]|via)\s+(formul[áa]rio (?:eletr[ôo]nico|online|on-line|do Google)|site do evento)'
$EvPlatforms = @(@('SIGAA', 'Pelo SIGAA'), @('Even3', 'Pela Even3'), @('Sympla', 'Pelo Sympla'), @('Doity', 'Pela Doity'))
# o que a seleção ou a chamada pede (k = só para esses tipos)
$EvReqs = @(
  @{ l = 'Artigo completo'; rx = & $EvRx 'artigos? (completo|in[ée]dito|cient[íi]fico)|submiss[ãa]o de artigos?|envio de artigos?|recebe(m)? artigos?' }
  @{ l = 'Resumo ou resumo expandido'; rx = & $EvRx 'resumos? expandidos?|envio de resumos?|submiss[ãa]o de resumos?' }
  @{ l = 'Apresentação oral ou pôster'; rx = & $EvRx 'comunica[çc][ãa]o oral|apresenta[çc][ãa]o oral|p[ôo]steres?\b|\bbanners?\b|grupos? de trabalho|\bGTs?\b' }
  @{ l = 'Pré-projeto de pesquisa'; rx = & $EvRx 'pr[ée]-?projeto|anteprojeto|projeto de pesquisa|proposta de pesquisa' }
  @{ l = 'Prova escrita'; rx = & $EvRx 'prova escrita|prova de conhecimentos?|prova te[óo]rica|exame escrito|avalia[çc][ãa]o escrita' }
  @{ l = 'Prova de língua estrangeira'; rx = & $EvRx 'profici[êe]ncia|l[íi]ngua estrangeira|prova de (ingl[êe]s|espanhol|franc[êe]s|idioma)' }
  @{ l = 'Entrevista ou defesa do projeto'; rx = & $EvRx 'entrevista|argui[çc][ãa]o|defesa (oral )?do (pr[ée]-?)?projeto' }
  @{ l = 'Análise do currículo (Lattes)'; rx = & $EvRx 'curr[íi]culo|lattes|an[áa]lise de t[íi]tulos|prova de t[íi]tulos' }
  @{ l = 'Carta de intenção ou memorial'; rx = & $EvRx 'carta de (inten[çc][ãa]o|motiva[çc][ãa]o)|memorial' }
  @{ l = 'Portfólio'; rx = & $EvRx 'portf[óo]lio' }
  @{ l = 'Diploma de graduação'; rx = & $EvRx 'diploma|gradua[çc][ãa]o conclu[íi]da|concluintes|portadores? de diploma'; k = 'edital curso' }
  @{ l = 'Reportagem ou trabalho já publicado'; rx = & $EvRx '(reportage(m|ns)|trabalhos?|mat[ée]rias?|produ[çc][õo]es) (publicad|veiculad|divulgad)'; k = 'premio' }
  @{ l = 'Filme, curta ou vídeo'; rx = & $EvRx 'curtas?(-metragem)?\b|longas?(-metragem)?\b|v[íi]deos?\b|filmes?\b'; k = 'festival premio' }
  @{ l = 'Dá para participar como ouvinte'; rx = & $EvRx '\bouvintes?\b'; k = 'congresso palestra curso evento' }
  @{ l = 'Pagamento de taxa'; rx = & $EvRx 'taxa de inscri[çc][ãa]o|\bGRU\b|boleto' }
)
$EvLinkSkip = & $EvRx 'facebook\.com|twitter\.com|x\.com/intent|whatsapp|wa\.me|linkedin\.com|instagram\.com|t\.me/|telegram|pinterest|mailto:|\.(jpe?g|png|gif|webp|svg)(\?|$)|/tag/|/category/|/author/|wp-login|/feed/?$|news\.google'
$EvLinkUrl = & $EvRx 'even3\.com|sympla\.com|doity\.com|sigaa|forms\.gle|docs\.google\.com/forms|typeform|jotform|inscri|submiss|edital|chamada|regulamento|\.pdf(\?|$)|/about/submissions'
$EvLinkText = & $EvRx 'inscri|edital|regulamento|submiss|formul[áa]rio|chamada|site do evento|programa[çc][ãa]o'
$EvAnchorRx = [regex]'(?is)<a\b[^>]*?href\s*=\s*["'']([^"''#][^"'']*)["''][^>]*>(.*?)</a>'

function Get-EvLinks([string]$Html, [string]$Base) {
  $out = New-Object Collections.ArrayList; $seen = @{}
  $self = ($Base -replace '[?#].*$', '').TrimEnd('/')
  foreach ($m in $EvAnchorRx.Matches($Html)) {
    $u = Resolve-Url $m.Groups[1].Value $Base
    if (-not $u -or $u -notmatch '^https?://' -or $EvLinkSkip.IsMatch($u) -or $seen.ContainsKey($u)) { continue }
    if (($u -replace '[?#].*$', '').TrimEnd('/') -eq $self) { continue }
    $t = ConvertFrom-Html $m.Groups[2].Value
    if (-not ($EvLinkUrl.IsMatch($u) -or $EvLinkText.IsMatch($t))) { continue }
    $seen[$u] = 1
    # nome do botão: o texto do link, ou o que o endereço diz quando o texto é "clique aqui" ou o próprio endereço
    if (-not $t -or $t.Length -lt 4 -or $t -match '^(clique|acesse|aqui|link|saiba|https?:|www\.)') {
      $t = if ($u -match 'even3') { 'Inscrição na Even3' } elseif ($u -match 'sympla') { 'Inscrição no Sympla' } elseif ($u -match 'doity') { 'Inscrição na Doity' } elseif ($u -match 'sigaa') { 'Inscrição no SIGAA' } elseif ($u -match 'forms') { 'Formulário de inscrição' } elseif ($u -match '\.pdf') { 'Edital (PDF)' } else { Get-EvHost $u }
    }
    $t = $t.Substring(0, 1).ToUpper() + $t.Substring(1)
    [void]$out.Add([ordered]@{ u = $u; t = (Limit-Text $t 60) })
    if ($out.Count -ge 3) { break }
  }
  # plataforma de inscrição primeiro
  , @($out | Sort-Object { if ($_.u -match 'even3|sympla|doity|sigaa|forms|typeform|jotform|inscri') { 0 } elseif ($_.u -match '\.pdf') { 1 } else { 2 } })
}
function Get-EvHost([string]$u) { try { ([Uri]$u).Host -replace '^www\.', '' } catch { $u } }

function Get-EvDetails([string]$Text, [string]$Html, [string]$Base, [string]$Kind) {
  if (-not $Text -or $Text.Length -lt 80) { return $null }
  $x = [ordered]@{}
  $fees = New-Object Collections.ArrayList; $prize = $null
  foreach ($m in $EvMoneyRx.Matches($Text)) {
    $pre = $Text.Substring([Math]::Max(0, $m.Index - 80), [Math]::Min(80, $m.Index))
    $v = $m.Value -replace '\s+', ' '
    if ($EvPrizeCtx.IsMatch($pre) -and -not $EvFeeCtx.IsMatch(($pre -split '[.;]')[-1])) { if (-not $prize) { $prize = $v } }
    elseif ($EvFeeCtx.IsMatch($pre) -and -not $fees.Contains($v)) { [void]$fees.Add($v) }
  }
  if ($fees.Count) { $x.val = ($fees | Select-Object -First 3) -join ' / '; if ($EvExemptRx.IsMatch($Text)) { $x.val += ' (com pedido de isenção)' } }
  elseif ($EvFreeRx.IsMatch($Text)) { $x.val = 'Gratuito' }
  if ($prize) { $x.pz = $prize }
  $s = $EvSeatsRx.Match($Text); if ($s.Success) { $x.vag = [int]$s.Groups[1].Value }
  # presencial/online e local só fazem sentido para o que acontece num lugar (não para edital, chamada ou prêmio)
  if ($Kind -notmatch '^(edital|chamada|premio)$') {
    $on = $EvOnlineRx.IsMatch($Text); $pr = $EvPresRx.IsMatch($Text)
    if ($EvHybridRx.IsMatch($Text) -or ($on -and $pr)) { $x.fmt = 'Presencial e online' } elseif ($on) { $x.fmt = 'Online' } elseif ($pr) { $x.fmt = 'Presencial' }
    $p = $EvPlaceRx.Match($Text)
    if ($p.Success) { $loc = ($p.Groups[1].Value -split ',')[0].Trim(); if ($loc -match '\s') { $x.loc = Limit-Text ($loc.Substring(0, 1).ToUpper() + $loc.Substring(1)) 70 } }
  }
  foreach ($pf in $EvPlatforms) { if ($Text -match "\b$($pf[0])\b") { $x.how = $pf[1]; break } }
  if (-not $x.how) { $h = $EvHowRx.Match($Text); if ($h.Success) { $x.how = 'Pelo ' + $h.Groups[1].Value } }
  $req = @(foreach ($r in $EvReqs) { if ((-not $r.k -or $r.k -split ' ' -contains $Kind) -and $r.rx.IsMatch($Text)) { $r.l } })
  if ($req.Count) { $x.req = $req }
  if ($Html) { $lk = Get-EvLinks $Html $Base; if ($lk.Count) { $x.lk = $lk } }
  $x.ex = Limit-Text $Text 650
  $x
}

# o miolo de uma página de notícia: parágrafos de verdade (sem menu nem rodapé), a partir do primeiro que fala do assunto
function Get-PageArticle([string]$Html, [string]$Title) {
  $paras = New-Object Collections.ArrayList
  foreach ($m in [regex]::Matches($Html, '(?is)<p\b[^>]*>(.*?)</p>')) {
    $t = ConvertFrom-Html $m.Groups[1].Value
    if ($t.Length -ge 50) { [void]$paras.Add(@{ t = $t; h = $m.Groups[1].Value }) }
  }
  $want = Get-EvWords $Title; $start = 0
  for ($i = 0; $i -lt [Math]::Min($paras.Count, 8); $i++) { if ((Get-EvOverlap $want (Get-EvWords $paras[$i].t)) -ge 0.25) { $start = $i; break } }
  $keep = @($paras | Select-Object -Skip $start -First 25)
  $desc = $null
  foreach ($m in $MetaRx.Matches($Html)) {
    if ($m.Value -match '(?i)(property|name)\s*=\s*["''](og:description|description)["'']') { $c = $ContentRx.Match($m.Value); if ($c.Success) { $desc = [Net.WebUtility]::HtmlDecode($c.Groups[1].Value).Trim(); break } }
  }
  # links só de dentro dos parágrafos da matéria (os do menu e da lateral ficam de fora)
  @{ text = (@($keep | ForEach-Object { $_.t }) -join ' '); html = (@($keep | ForEach-Object { $_.h }) -join "`n"); desc = $desc }
}

# a mesma notícia em vários veículos: palavras que sobram tirando as genéricas
$EvGeneric = New-Object 'Collections.Generic.HashSet[string]' (, [string[]]('encontro seminario congresso simposio coloquio conferencia jornada forum evento eventos comunicacao jornalismo publicidade design midia midias ' +
  'ufpb paraiba fortaleza ceara joao pessoa inscricoes abre abertas recebe realiza promove sedia debate sobre para como mais edicao anos nacional internacional ' +
  'regional brasil brasileiro brasileira programa curso cursos oficina palestra revista chamada artigos dossie tematico futuro com dos das nas nos uma ' +
  'esta este estao isso pelo pela pelos pelas entre sera serao novo nova novos novas ainda apos traz reune reunem discute acontece ' +
  'ultimos ultimo dias semana proximo proxima hoje amanha domingo segunda terca quarta quinta sexta sabado terminam termina comecam comeca inscricao').Split(' '))
function Get-EvTokens([string]$t) {
  $n = [regex]::Replace($t.ToLowerInvariant().Normalize([Text.NormalizationForm]::FormD), '\p{Mn}', '')
  $set = New-Object 'Collections.Generic.HashSet[string]'
  foreach ($w in ($n -split '[^a-z0-9]+')) {
    if ((($w.Length -ge 4 -and $w -notmatch '^20\d\d$') -or ($w -match '^\d{2,3}$')) -and -not $EvGeneric.Contains($w)) { [void]$set.Add($w) }
  }
  , $set
}
function Test-EvSame($a, $b) {
  if ($a.Count -lt 2 -or $b.Count -lt 2) { return $false }
  $n = 0; foreach ($w in $a) { if ($b.Contains($w)) { $n++ } }
  $n -ge 2 -and $n / [Math]::Min($a.Count, $b.Count) -ge 0.6
}

# ---------- coleta ----------
# a busca pega 45 dias (para achar o que tem data), mas notícia sem data só fica 3 semanas
$gnews = [pscustomobject]@{ id = 'gnews'; name = 'Google Notícias'; site = 'https://news.google.com'; lang = 'pt'; days = 21 }
$evBySrc = [ordered]@{}
foreach ($s in @($evCfg.sources)) { $s | Add-Member -NotePropertyName lang -NotePropertyValue 'pt' -Force; $evBySrc[$s.url] = $s }
foreach ($q in @($evCfg.news)) {
  $evBySrc['https://news.google.com/rss/search?q=' + [Uri]::EscapeDataString("$q when:45d") + '&hl=pt-BR&gl=BR&ceid=BR:pt-419'] = $gnews
}
$evSrcIds = @{ gnews = $gnews }; foreach ($s in @($evCfg.sources)) { $evSrcIds[$s.id] = $s }

$evPrev = @{}
if (Test-Path $evOut) {
  try {
    $old = Get-Content -Raw -Encoding UTF8 $evOut | ConvertFrom-Json
    foreach ($o in $old.items) {
      $h = [ordered]@{}
      foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = $p.Value }
      # o pwsh 7 transforma texto de data em DateTime ao ler JSON: volta para texto
      foreach ($k in 'at', 'fs') { if ($h[$k] -is [DateTime]) { $h[$k] = ([DateTimeOffset]([DateTime]$h[$k]).ToUniversalTime()).ToString('o') } }
      foreach ($k in 'w', 'we', 'ds', 'dl') { if ($h[$k] -is [DateTime]) { $h[$k] = ([DateTime]$h[$k]).ToString('yyyy-MM-dd') } }
      $evPrev[$h.id] = $h
    }
  } catch { Write-Warning "Não deu para ler a agenda anterior: $($_.Exception.Message)" }
}

Write-Host "Agenda: buscando $($evBySrc.Count) fontes e buscas..."
$evFetched = Get-Many ([string[]]@($evBySrc.Keys)) $script:Http
$evStatus = @{}; $evFresh = [ordered]@{}
foreach ($u in @($evBySrc.Keys)) {
  $src = $evBySrc[$u]
  $r = $evFetched[$u]
  $label = $src.id
  if ($src.id -eq 'gnews') { $q = [Uri]::UnescapeDataString(($u -replace '^.*\?q=', '' -replace '&.*$', '')); $label = 'gnews: ' + $q.Substring(0, [Math]::Min(40, $q.Length)) }
  if ($r.err) { if ($evStatus[$src.id] -ne 'ok') { $evStatus[$src.id] = $r.err }; Write-Host ("  x {0,-48} {1}" -f $label, $r.err); continue }
  try {
    $doc = Read-Feed (ConvertTo-Text $r.bytes $r.charset)
    $n = 0
    foreach ($node in $doc.SelectNodes("//*[local-name()='item' or local-name()='entry']")) {
      $x = Read-EvNode $node $src
      if (-not $x -or $evFresh.Contains($x.it.id)) { continue }
      $x.src = $src
      $evFresh[$x.it.id] = $x; $n++
    }
    $evStatus[$src.id] = 'ok'
    Write-Host ("  ok {0,-47} {1} itens" -f $label, $n)
  } catch {
    if ($evStatus[$src.id] -ne 'ok') { $evStatus[$src.id] = $_.Exception.Message }
    Write-Host ("  x {0,-48} {1}" -f $label, $_.Exception.Message)
  }
}

$evKept = New-Object Collections.ArrayList
$evTok = @{}
# repetida: completa a que ficou com data, cidade e região que só a outra trazia
function Add-EvKept($e) {
  $tk = Get-EvTokens $e.t
  foreach ($k in $evKept) {
    # mesma fonte falando do mesmo dia de evento também é repetida (programação, hospedagem, inscrições...)
    $sameDay = $k.s -eq $e.s -and $e.w -and $e.w.Length -eq 10 -and $k.w -eq $e.w
    if (-not $sameDay -and -not (Test-EvSame $tk $evTok[$k.id])) { continue }
    if (-not $k.w -and $e.w) { $k.w = $e.w; $k.we = $e.we }
    if (-not $k.dl -and $e.dl) { $k.dl = $e.dl; $k.ds = $e.ds }
    if ($k.r -eq 'br' -and $e.r -ne 'br') { $k.r = $e.r }
    if (-not $k.pl -and $e.pl -and $k.r -eq $e.r) { $k.pl = $e.pl }
    if ($e.m) { $k.m = 1 }
    return
  }
  $evTok[$e.id] = $tk
  [void]$evKept.Add($e)
}
foreach ($x in $evFresh.Values) {
  $it = $x.it; $src = $x.src
  $at = ConvertTo-Date $it.at
  if (-not $at) { $at = $evNow }
  if ($at -gt $evNow.AddHours(1)) { $at = $evNow }
  $info = Get-EvInfo $it $src $x.body $at.ToOffset([TimeSpan]::FromHours(-3)).DateTime.Date $x.pub
  if (-not $info) { continue }
  $days = $(if ($src.days) { [int]$src.days } else { 60 })
  if (-not (Test-EvAlive $info $at $days)) { continue }
  $p = $evPrev[$it.id]
  Add-EvKept ([ordered]@{
    id = $it.id; s = $src.id; u = $it.u; pub = $x.pub; t = $it.t; d = (Limit-Text $it.d 260)
    at = $at.ToString('o'); fs = $(if ($p -and $p.fs) { $p.fs } else { $evNowIso })
    k = $info.k; r = $info.r; pl = $info.pl; w = $info.w; we = $info.we; ds = $info.ds; dl = $info.dl; m = $(if ($info.m) { 1 } else { $null })
    x = $null; ru = $null; dx = $null
    # só para esta rodada (não vão pro arquivo): texto e HTML da notícia, site do veículo
    _body = $x.body; _html = $x.html; _site = $x.site
  })
}
# o que saiu dos feeds continua enquanto a data não passar
foreach ($p in $evPrev.Values) {
  if ($evFresh.Contains($p.id) -or -not $evSrcIds.ContainsKey($p.s)) { continue }
  $at = ConvertTo-Date $p.at
  if (-not $at) { continue }
  $src = $evSrcIds[$p.s]
  if (-not (Test-EvAlive $p $at $(if ($src.days) { [int]$src.days } else { 60 }))) { continue }
  foreach ($k in 'w', 'we', 'ds', 'dl', 'pl', 'pub', 'd', 'm', 'x', 'ru', 'dx') { if (-not $p.Contains($k)) { $p[$k] = $null } }
  Add-EvKept $p
}

# ---------- detalhes ----------
# Quem veio com texto (UFPB, UECE, revistas, associações) já tem os detalhes aqui. As do Google Notícias só trazem
# o título e um link do Google: o Bing Notícias acha a matéria original pelo título e a página é lida direto.
$evLookup = New-Object Collections.ArrayList
foreach ($e in $evKept) {
  if ($e._body) { $e.x = Get-EvDetails $e._body $e._html $e.u $e.k; continue }
  $p = $evPrev[$e.id]
  if ($p -and $p.dx) { foreach ($k in 'x', 'ru', 'dx') { $e[$k] = $p[$k] }; if (-not $e.d -and $p.d) { $e.d = $p.d }; continue }
  if ($e.s -eq 'gnews' -and -not $e.dx -and $evLookup.Count -lt 15) { [void]$evLookup.Add($e) }
}
$EvStopWords = New-Object 'Collections.Generic.HashSet[string]' (, [string[]]('de da do das dos em no na nos nas para por com e o a os as um uma que ao aos se sua seu'.Split(' ')))
function Get-EvWords([string]$t) {
  $n = [regex]::Replace($t.ToLowerInvariant().Normalize([Text.NormalizationForm]::FormD), '\p{Mn}', '')
  , @($n -split '[^a-z0-9]+' | Where-Object { $_.Length -ge 2 -and -not $EvStopWords.Contains($_) } | Select-Object -Unique)
}
function Get-EvOverlap($a, $b) {
  if (-not $a.Count) { return 0 }
  $n = 0; foreach ($w in $a) { if ($b -contains $w) { $n++ } }
  $n / $a.Count
}
# outra matéria sobre o mesmo assunto também serve: pelo menos 3 palavras em comum, medidas pelo título mais curto
function Get-EvMatch($a, $b) {
  $n = 0; foreach ($w in $a) { if ($b -contains $w) { $n++ } }
  if ($n -lt 3) { return 0 }
  $n / [Math]::Min($a.Count, $b.Count)
}
function Read-EvPage($r) {
  $len = [Math]::Min($r.bytes.Length, 800000)
  $enc = [Text.Encoding]::UTF8
  if ($r.charset) { try { $enc = [Text.Encoding]::GetEncoding($r.charset.Trim('"')) } catch { } }
  $enc.GetString($r.bytes, 0, $len)
}
if ($evLookup.Count) {
  Write-Host "Agenda: procurando a matéria original de $($evLookup.Count) notícias..."
  $search = @{}
  foreach ($e in $evLookup) { $e.dx = 1; $search[$e.id] = 'https://www.bing.com/news/search?q=' + [Uri]::EscapeDataString($e.t) + '&format=rss&setlang=pt-BR&cc=BR' }
  $found = Get-Many ([string[]]@($search.Values)) $script:Http 8
  $pages = @{}; $wpSearch = @{}
  foreach ($e in $evLookup) {
    $want = Get-EvWords $e.t; $best = $null; $bestScore = 0
    $r = $found[$search[$e.id]]
    if ($r -and -not $r.err) {
      try {
        $doc = Read-Feed (ConvertTo-Text $r.bytes $r.charset)
        foreach ($n in $doc.SelectNodes("//*[local-name()='item']")) {
          $l = Get-Text $n "*[local-name()='link']"
          if ($l -match '[?&]url=([^&]+)') { $l = [Uri]::UnescapeDataString($Matches[1]) }
          if ($l -notmatch '^https?://') { continue }
          $score = Get-EvMatch $want (Get-EvWords (ConvertFrom-Html (Get-Text $n "*[local-name()='title']")))
          if ($score -gt $bestScore) { $bestScore = $score; $best = $l }
        }
      } catch { }
    }
    if ($best -and $bestScore -ge 0.7) { $e.ru = $best; $pages[$best] = $e }
    elseif ($e._site) {
      # sem o Bing: muitos veículos são WordPress e a busca do próprio site devolve a matéria inteira
      $q = (@($want) | Select-Object -First 7) -join ' '
      $wpSearch[$e._site.TrimEnd('/') + '/?s=' + [Uri]::EscapeDataString($q) + '&feed=rss2'] = $e
    }
  }
  $got = Get-Many ([string[]]@(@($pages.Keys) + @($wpSearch.Keys))) $script:PageHttp 8
  $ok = 0
  foreach ($u in @($pages.Keys)) {
    $e = $pages[$u]; $r = $got[$u]
    if (-not $r -or $r.err) { continue }
    $art = Get-PageArticle (Read-EvPage $r) $e.t
    if (-not $e.d -and $art.desc) { $e.d = Limit-Text $art.desc 260 }
    $e._body = $art.text; $e.x = Get-EvDetails $art.text $art.html $u $e.k
    if ($e.x) { $ok++ }
  }
  foreach ($u in @($wpSearch.Keys)) {
    $e = $wpSearch[$u]; $r = $got[$u]
    if (-not $r -or $r.err) { continue }
    try {
      $doc = Read-Feed (ConvertTo-Text $r.bytes $r.charset)
      foreach ($n in $doc.SelectNodes("//*[local-name()='item']")) {
        if ((Get-EvMatch (Get-EvWords $e.t) (Get-EvWords (ConvertFrom-Html (Get-Text $n "*[local-name()='title']")))) -lt 0.7) { continue }
        $html = Get-Markup $n $XP.content
        if (-not $html) { $html = Get-Markup $n $XP.desc }
        $e.ru = Get-Text $n "*[local-name()='link']"
        $e._body = ConvertFrom-Html $html
        if (-not $e.d) { $e.d = Limit-Text (Clear-Summary (ConvertFrom-Html (Get-Markup $n $XP.desc))) 260 }
        $e.x = Get-EvDetails $e._body $html $e.ru $e.k
        if ($e.x) { $ok++ }
        break
      }
    } catch { }
  }
  # o texto completo pode trazer as datas que o título não tinha
  foreach ($e in $evLookup) {
    if (-not $e._body -or $e.w -or $e.dl -or $e.ds) { continue }
    $dt = Get-EvDates @($e.t, $e.d, (Get-Start $e._body 2500)) (ConvertTo-Date $e.at).ToOffset([TimeSpan]::FromHours(-3)).DateTime.Date
    foreach ($k in 'w', 'we', 'ds', 'dl') { if ($dt[$k]) { $e[$k] = $dt[$k] } }
    if ($e.w -or $e.dl -or $e.ds) { $e._dead = -not (Test-EvAlive $e (ConvertTo-Date $e.at) 21) }
  }
  Write-Host "  detalhes de $ok"
}
$evKept = @($evKept | Where-Object { -not $_._dead })

# ---------- gravação ----------
$evPrio = { param($e) if ($e.m) { 3 } elseif ($e.r -eq 'jp' -or $e.r -eq 'ce') { 2 } elseif ($e.r -eq 'ne') { 1 } else { 0 } }
$evItems = @($evKept | Sort-Object @{ e = { & $evPrio $_ }; Descending = $true }, @{ e = { $_.fs }; Descending = $true } | Select-Object -First 160 | ForEach-Object {
  $o = [ordered]@{}
  foreach ($k in 'id', 's', 'u', 'ru', 'pub', 't', 'd', 'at', 'fs', 'k', 'r', 'pl', 'w', 'we', 'ds', 'dl', 'm', 'x', 'dx') {
    $v = $_[$k]
    if ($null -eq $v -or ($v -is [string] -and $v -eq '')) { continue }
    $o[$k] = $v
  }
  $o
})
$evCounts = @{}; foreach ($e in $evItems) { $evCounts[$e.s] = 1 + [int]$evCounts[$e.s] }
$evData = [ordered]@{
  v = 1
  updated = $evNowIso
  sources = @(@($evCfg.sources) + $gnews | ForEach-Object { [ordered]@{ id = $_.id; name = $_.name; site = $_.site; n = [int]$evCounts[$_.id]; ok = ($evStatus[$_.id] -eq 'ok') } })
  items = $evItems
}
New-Item -ItemType Directory -Force (Split-Path $evOut) | Out-Null
[IO.File]::WriteAllText($evOut, (ConvertTo-Json $evData -Depth 8 -Compress), (New-Object Text.UTF8Encoding $false))
$byRegion = ($evItems | Group-Object { $_.r } | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ' '
Write-Host "Agenda gravada: $($evItems.Count) eventos ($byRegion), $(@($evItems | Where-Object { $_.m }).Count) de mestrado -> $evOut"
