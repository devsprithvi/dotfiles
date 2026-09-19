import { spawnSync } from "node:child_process";
import {
  workspace,
  window,
  commands,
  ExtensionContext,
  OutputChannel,
} from "vscode";
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
  TransportKind,
  RevealOutputChannelOn,
} from "vscode-languageclient/node";

let client: LanguageClient | undefined;
let output: OutputChannel;

export async function activate(context: ExtensionContext): Promise<void> {
  output = window.createOutputChannel("pulipil");
  context.subscriptions.push(output);

  context.subscriptions.push(
    commands.registerCommand("pulipil.restartServer", async () => {
      output.appendLine("Restarting pulipil language server…");
      await stopClient();
      await startClient(context);
    }),
  );

  await startClient(context);
}

export async function deactivate(): Promise<void> {
  await stopClient();
}

async function startClient(context: ExtensionContext): Promise<void> {
  const config = workspace.getConfiguration("pulipil");
  const serverPath = config.get<string>("server.path", "pulipil");
  const serverArgs = config.get<string[]>("server.args", ["lsp", "--stdio"]);

  if (!binaryIsRunnable(serverPath)) {
    const choice = await window.showErrorMessage(
      `Could not run the pulipil language server ('${serverPath}'). ` +
        `Install pulipil and ensure it is on your PATH, or set 'pulipil.server.path'.`,
      "Open Settings",
    );
    if (choice === "Open Settings") {
      await commands.executeCommand(
        "workbench.action.openSettings",
        "pulipil.server.path",
      );
    }
    return;
  }

  // The server communicates over stdio. stdout carries the JSON-RPC stream;
  // the server keeps all human-facing logging on stderr.
  const serverOptions: ServerOptions = {
    run: { command: serverPath, args: serverArgs, transport: TransportKind.stdio },
    debug: { command: serverPath, args: serverArgs, transport: TransportKind.stdio },
  };

  const clientOptions: LanguageClientOptions = {
    // Scope the client to CUE documents. pulipil manifests are CUE files
    // (conventionally pulipil.cue), so we drive completion for the whole
    // language and let the server decide when a buffer is a pulipil manifest.
    documentSelector: [
      { scheme: "file", language: "cue" },
      { scheme: "file", pattern: "**/pulipil.cue" },
      { scheme: "file", pattern: "**/*.pulipil.cue" },
    ],
    synchronize: {
      fileEvents: workspace.createFileSystemWatcher("**/pulipil.cue"),
    },
    outputChannel: output,
    revealOutputChannelOn: RevealOutputChannelOn.Never,
  };

  client = new LanguageClient(
    "pulipil",
    "pulipil language server",
    serverOptions,
    clientOptions,
  );

  try {
    await client.start();
    output.appendLine(
      `pulipil language server started (${serverPath} ${serverArgs.join(" ")}).`,
    );
  } catch (err) {
    output.appendLine(`Failed to start pulipil language server: ${String(err)}`);
    window.showErrorMessage(
      "pulipil language server failed to start. See the pulipil output channel for details.",
    );
  }
}

async function stopClient(): Promise<void> {
  if (client) {
    await client.stop();
    client = undefined;
  }
}

// binaryIsRunnable does a cheap `--version`-style probe so activation fails
// loudly and early with an actionable message instead of a silent no-op.
function binaryIsRunnable(bin: string): boolean {
  try {
    const res = spawnSync(bin, ["lsp", "--info"], {
      timeout: 5000,
      stdio: "ignore",
    });
    return res.status === 0;
  } catch {
    return false;
  }
}
