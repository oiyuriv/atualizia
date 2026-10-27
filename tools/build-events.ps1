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
  '\br[áa]dio|televis|streaming|ilustra[çc]|quadrinhos|\bPPGC\b|\bPPGJ\b|PPGCOM|intercom|comp[óo]s\b|socine|abrapcorp|sbpjor|expocom|desinforma|checagem|influenciad')
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
    if ($null -ne $sn) { $pub = $sn.InnerText.Trim() }
    if ($pub -and $it.t.EndsWith(" - $pub")) { $it.t = $it.t.Substring(0, $it.t.Length - $pub.Length - 3).Trim() }
    elseif ($it.t -match '^(.*\S)\s+-\s+([^-]{2,80})$') { $it.t = $Matches[1]; if (-not $pub) { $pub = $Matches[2].Trim() } }
    $it.d = ''
  }
  # o texto inteiro ajuda a achar as datas; avisos de revista vêm só na descrição
  $body = ConvertFrom-Html (Get-Markup $Node $XP.content)
  if (-not $body) { $body = ConvertFrom-Html (Get-Markup $Node $XP.desc) }
  if ($body.Length -gt 2500) { $body = $body.Substring(0, 2500) }
  @{ it = $it; body = $body; pub = $pub }
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
  $dates = Get-EvDates @($It.t, $It.d, $Body) $Pub
  @{ k = $kind; r = $region; pl = $city; w = $dates.w; we = $dates.we; ds = $dates.ds; dl = $dates.dl; m = $mest }
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
  })
}
# o que saiu dos feeds continua enquanto a data não passar
foreach ($p in $evPrev.Values) {
  if ($evFresh.Contains($p.id) -or -not $evSrcIds.ContainsKey($p.s)) { continue }
  $at = ConvertTo-Date $p.at
  if (-not $at) { continue }
  $src = $evSrcIds[$p.s]
  if (-not (Test-EvAlive $p $at $(if ($src.days) { [int]$src.days } else { 60 }))) { continue }
  foreach ($k in 'w', 'we', 'ds', 'dl', 'pl', 'pub', 'd', 'm') { if (-not $p.Contains($k)) { $p[$k] = $null } }
  Add-EvKept $p
}

# ---------- gravação ----------
$evPrio = { param($e) if ($e.m) { 3 } elseif ($e.r -eq 'jp' -or $e.r -eq 'ce') { 2 } elseif ($e.r -eq 'ne') { 1 } else { 0 } }
$evItems = @($evKept | Sort-Object @{ e = { & $evPrio $_ }; Descending = $true }, @{ e = { $_.fs }; Descending = $true } | Select-Object -First 160 | ForEach-Object {
  $o = [ordered]@{}
  foreach ($k in 'id', 's', 'u', 'pub', 't', 'd', 'at', 'fs', 'k', 'r', 'pl', 'w', 'we', 'ds', 'dl', 'm') {
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
[IO.File]::WriteAllText($evOut, (ConvertTo-Json $evData -Depth 5 -Compress), (New-Object Text.UTF8Encoding $false))
$byRegion = ($evItems | Group-Object { $_.r } | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ' '
Write-Host "Agenda gravada: $($evItems.Count) eventos ($byRegion), $(@($evItems | Where-Object { $_.m }).Count) de mestrado -> $evOut"
