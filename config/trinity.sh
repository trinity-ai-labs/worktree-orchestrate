# Per-project worktree config for a checkout named `trinity` (the repo's default
# clone dir — `gh repo clone trinity-ai-labs/trinity` → ./trinity).
#
# It is the SAME project as `trinity-ai-labs` (a renamed checkout of the same
# repo), so this file must stay identical to trinity-ai-labs.sh. To guarantee
# that — and never drift again — it just delegates to the canonical config
# instead of holding its own copy.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/trinity-ai-labs.sh"
