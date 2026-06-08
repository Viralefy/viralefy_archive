---
name: no-secret-rotation-nag
description: "Don't nag about rotating leaked secrets unless asked; current env is HML/POC."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 156ce2c8-a44d-4b68-83b1-2ec311c4d144
---

In Viralefy work, do **not** spontaneously remind the user to rotate SSH keys,
Resend API keys, or any other credential that was previously pasted in chat.
The environment is HML / POC running a 15-day result test (until ~2026-06-14).
If results justify scaling to PRD they'll handle rotation themselves.

**Why:** the user said verbatim "rotacionar chaves não é necessário nesse
momento, pare de me alertar." Repeating the warning is friction without
value — they've acknowledged the risk and accepted it for the POC window.

**How to apply:**
- Use credentials in `/media/sonne/Archives/projects/viralefy/credentials`
  for deploy without flagging it.
- Don't add rotation TODOs to CONTEXT.md débitos when summarizing work.
- If the user asks how to rotate, then explain — only when prompted.
- Reconsider after 2026-06-14 if the POC scales: at PRD-cutover ask once
  whether rotation should be done before exposing more surface.

Related: [[viralefy-features-v2]], [[viralefy-ops-and-github]].
