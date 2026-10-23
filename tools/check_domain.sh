#!/usr/bin/env bash
# Checks the custom domain of the site and its business mailbox, using public DNS and HTTPS only.
# Usage: bash tools/check_domain.sh masarmetro.sa
# Prints one line per check (PASS / FAIL / WAIT) and a summary table to $GITHUB_STEP_SUMMARY when set.
# Exits 1 if a check the site needs fails. Mail checks only warn, since the mailbox is set up after the site.
set -uo pipefail

D="${1:?domain required, e.g. masarmetro.sa}"
PAGES_A="185.199.108.153 185.199.109.153 185.199.110.153 185.199.111.153"
NS=1.1.1.1
fail=0
rows=()
feed=$(mktemp)
trap 'rm -f "$feed"' EXIT

q() { dig +short +time=5 +tries=2 "@$NS" "$@" 2>/dev/null; }
log() { # status, check, detail
  printf '%-5s %-22s %s\n' "$1" "$2" "$3"
  rows+=("| $1 | $2 | $3 |")
  [ "$1" = FAIL ] && fail=1
  return 0
}

# 1. The domain is delegated (registered and approved)
ns=$(q NS "$D" | tr '\n' ' ')
if [ -n "$ns" ]; then log PASS "Domain registered" "NS: $ns"; else log FAIL "Domain registered" "no NS records yet: still pending approval, or not registered"; fi

# 2. Apex points at GitHub Pages
a=$(q A "$D" | sort | tr '\n' ' ')
missing=""; for ip in $PAGES_A; do case " $a " in *" $ip "*) ;; *) missing+="$ip ";; esac; done
if [ -z "$a" ]; then log FAIL "A records (@)" "none"
elif [ -n "$missing" ]; then log FAIL "A records (@)" "have: $a | missing: $missing"
else
  extra=""; for ip in $a; do case " $PAGES_A " in *" $ip "*) ;; *) extra+="$ip ";; esac; done
  if [ -n "$extra" ]; then log FAIL "A records (@)" "remove extra: $extra"; else log PASS "A records (@)" "$a"; fi
fi
aaaa=$(q AAAA "$D" | tr '\n' ' ')
case "$aaaa" in *2606:50c0:800*) log PASS "AAAA records (@)" "$aaaa";; "") log WAIT "AAAA records (@)" "none (optional, recommended)";; *) log FAIL "AAAA records (@)" "unexpected: $aaaa";; esac

# 3. www points at the GitHub user domain
www=$(q CNAME "www.$D" | tr '\n' ' ')
case "$www" in *monerah-giv.github.io*) log PASS "www CNAME" "$www";; "") log FAIL "www CNAME" "none, expected monerah-giv.github.io";; *) log FAIL "www CNAME" "$www, expected monerah-giv.github.io";; esac

# 4. The site answers over HTTPS with the Masar feed
code=$(curl -s -o "$feed" -w '%{http_code}' --max-time 15 "https://$D/ads.json" || true)
if [ "$code" = 200 ] && grep -q '"campaigns"' "$feed"; then log PASS "HTTPS site" "https://$D/ads.json answers 200"
else
  code_http=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "http://$D/" || true)
  log FAIL "HTTPS site" "https status $code (http status $code_http): set Custom domain in Pages settings, wait for the certificate, then Enforce HTTPS"
fi
if [ "$code" = 200 ] && grep -q "info@$D" "$feed"; then log PASS "Feed contact email" "info@$D"
else log WAIT "Feed contact email" "not info@$D yet: merge the custom-domain pull request"; fi

# 5. Mail (warnings only)
mx=$(q MX "$D" | sort -n | tr '\n' ' ')
if [ -n "$mx" ]; then log PASS "MX" "$mx"; else log WAIT "MX" "none: add the MX records from the mail provider"; fi
spf=$(q TXT "$D" | grep -i 'v=spf1' | tr '\n' ' ')
n_spf=$(q TXT "$D" | grep -ci 'v=spf1')
if [ "$n_spf" -gt 1 ]; then log FAIL "SPF" "$n_spf SPF records: keep exactly one"
elif [ -n "$spf" ]; then log PASS "SPF" "$spf"; else log WAIT "SPF" "none"; fi
dk=$(q TXT "zoho._domainkey.$D" | head -c 60)
if [ -n "$dk" ]; then log PASS "DKIM (zoho)" "$dk..."; else log WAIT "DKIM (zoho)" "none at zoho._domainkey (another provider uses another selector)"; fi
dm=$(q TXT "_dmarc.$D" | tr '\n' ' ')
case "$dm" in *DMARC1*) log PASS "DMARC" "$dm";; *) log WAIT "DMARC" "none";; esac

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  { echo "### Domain check: $D"; echo; echo "| Result | Check | Detail |"; echo "| --- | --- | --- |"; printf '%s\n' "${rows[@]}"; } >> "$GITHUB_STEP_SUMMARY"
fi
exit $fail
