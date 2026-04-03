import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { basename } from "node:path";

// Workaround: pi doesn't update the terminal title on setSessionName() or
// session switch. Once pi fixes this, the setTitle calls can be removed.
export default function (pi: ExtensionAPI) {
  const syncTitle = (ctx: { ui: { setTitle(t: string): void } }) => {
    const name = pi.getSessionName();
    const cwd = basename(process.cwd());
    ctx.ui.setTitle(name ? `\u03c0 - ${name} - ${cwd}` : `\u03c0 - ${cwd}`);
  };

  pi.on("session_switch", async (_event, ctx) => syncTitle(ctx));

  pi.on("agent_end", async (event, ctx) => {
    if (pi.getSessionName()) return;
    const msg = event.messages.find((m) => m.role === "user");
    if (!msg) return;
    const text =
      typeof msg.content === "string"
        ? msg.content
        : msg.content
            .filter((b) => b.type === "text")
            .map((b) => (b as { text: string }).text)
            .join(" ");
    const name = text.slice(0, 60).replace(/\n/g, " ").trim();
    if (name) {
      pi.setSessionName(name);
      syncTitle(ctx);
    }
  });
}
