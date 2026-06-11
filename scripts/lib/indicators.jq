# Pure indicator math. Input: array of bars {t,o,h,l,c,v} sorted ascending,
# >= 51 bars. Output: [last_close, atr14, rsi14, sma20, sma50, relvol, a1, a2].
# Simplifications (documented): ATR = simple mean of last 14 true ranges (not
# Wilder smoothing); RSI = simple mean gains/losses over last 14 deltas.
# Note: the last bar is today's PARTIAL bar when run intraday - relvol reads low and a1/a2 can shift during the session.
def abs2: if . < 0 then -. else . end;
def round2: . * 100 | round / 100;

def indicators:
  . as $b
  | ($b | length) as $n
  | (if $n < 51 then error("insufficient bars: \($n) < 51") else . end)
  | ($b | map(.c)) as $c
  | ([range(1; $n) | [ ($b[.].h - $b[.].l),
                       (($b[.].h - $c[. - 1]) | abs2),
                       (($b[.].l - $c[. - 1]) | abs2) ] | max]) as $tr
  | ($tr[-14:] | add / 14) as $atr
  | ([range($n - 14; $n) | $c[.] - $c[. - 1]]) as $d
  | ($d | map(if . > 0 then . else 0 end) | add / 14) as $gain
  | ($d | map(if . < 0 then -. else 0 end) | add / 14) as $loss
  | (if $loss == 0 then (if $gain == 0 then 50 else 100 end)
     else 100 - (100 / (1 + ($gain / $loss))) end) as $rsi
  | ($c[-20:] | add / 20) as $sma20
  | ($c[-50:] | add / 50) as $sma50
  | ($b | map(.v)) as $v
  | (if ($v[-21:-1] | add) == 0 then 0
     else $v[-1] / (($v[-21:-1] | add) / 20) end) as $relvol
  | ($b[-7:]  | map(.l) | min) as $a1
  | ($b[-35:] | map(.l) | min) as $a2
  | [ ($c[-1]|round2), ($atr|round2), ($rsi|round), ($sma20|round2), ($sma50|round2),
      ($relvol|round2), ($a1|round2), ($a2|round2) ];
