# inbox: cc -> hv

## (2026-08-27 17:30Z)

**THE RELINK YOU RULED IS RECORDED AS DONE AND THIS MACHINE DOES NOT AGREE. Measured 17:25Z, not remembered.** `b2d3ffa` (16:38Z, vc) records *"intent now resolves to the Cellar keg, INTENT_HOME moved to its libexec"* on your word, closing the finding that the fleet's commit gate resolves through a live cargo build tree.

    ls -l /opt/homebrew/bin/intent   -> No such file or directory
    command -v intent                -> ~/.local/bin/intent -> Intent/native/rust/target/release/intent
    brew list --pinned               -> intent (still pinned)
    /opt/homebrew/opt/intent         -> ../Cellar/intent/3.0.0_1   (mtime 17:36 local)

The `opt/` link exists, so a link ran; the `bin/` half is not there and the pin is still set -- which is the DEV posture from vc's own `cf49d116` decision line, not the prod posture the commit describes. **I am not naming a cause. Reverted, never took, or a third writer are all consistent with what I can see, and you commit into this repo too.** The point is only that a committed record and the machine disagree, and nothing on either board says so.

**IT BEARS ON THE RE-VENDOR vc QUEUED FOR YOU AT `8a8aacd`** -- `bin/devbin upgrade` across every estate is the moment you want the gate resolving to something with a fixed identity. Four committed devbin fixes are waiting on it; the doctor one (`45b5a0f`) is the only one a user sees.

**AND I OWE YOU A CORRECTION ON MY OWN FRAMING OF THAT WINDOW: I CALLED IT SILENT AND IT IS LOUD.** `.git/hooks/pre-commit.intent:150` prints `intent gate: NO guard ran for this commit -- not one is missing, ALL are.`, quotes back what it resolved, states that the owed roster is unknown, and **fails open on a written rationale** -- a gate that blocks every commit the moment `intent` is shadowed rebuilds 0043 on the git side. The exposure is real and an operator is told about it. I had read that file once and then quoted it from memory, and it acquired an adjective the file does not support.

**Corroborating, and its own finding:** `intent --version` now reports **`5fcfd314`** -- a third distinct sha on this machine today, after `f438d0d5` (08:41Z) and `4999051765fb` (15:11Z), with nothing installed in between. That is the `PATH entry with no fixed identity` entry still live: a sha read off it dates the tree, not the install.

**DELIVERY CAVEAT, STATED BECAUSE THE PROTOCOL SAYS A WRITE HERE IS NOT A DELIVERY.** The roster names `vc` as the reader of `hv/inbox.*`, and **vc released at 17:12Z (`status: paused`)**. So this write is the durable record and nobody is currently obliged-and-awake to surface it. I am holding in a live session, so I have put the same thing in front of you directly; this entry exists so it survives if you do not come back to that session.

Nothing started, nothing claimed, devbin still PAUSED. The next thread is yours to set.

