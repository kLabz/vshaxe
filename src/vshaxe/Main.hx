package vshaxe;

import vscode.*;
import Vscode.*;
import haxe.Constraints.Function;

class ClientServer {
    public var client:LanguageClient;
    public var server:Disposable;
    public var fileWatcher:FileSystemWatcher;

    public function new(context:ExtensionContext, client:LanguageClient, suffix:String) {
        this.client = client;
        client.onReady().then(function(_) {
            client.outputChannel.appendLine(suffix + " language server started");
            fileWatcher = workspace.createFileSystemWatcher("**/*." + suffix, false, true, true);
            context.subscriptions.push(fileWatcher);
        });
        var serverDisposable = client.start();
        context.subscriptions.push(serverDisposable);
        server = serverDisposable;
    }

    public function stop(context:ExtensionContext) {
        if (client != null && client.outputChannel != null)
            client.outputChannel.dispose();

        if (server != null) {
            context.subscriptions.remove(server);
            server.dispose();
            server = null;
        }

        if (fileWatcher != null) {
            context.subscriptions.remove(fileWatcher);
            fileWatcher.dispose();
            fileWatcher = null;
        }
    }
}

class Main {
    var context:ExtensionContext;
    var hx:ClientServer;
    // var hxml:ClientServer;
    var vshaxeChannel:OutputChannel;
    var displayConfig:DisplayConfiguration;

    function new(ctx) {
        context = ctx;

        displayConfig = new DisplayConfiguration(ctx);
        new InitProject(ctx);

        registerCommand("restartLanguageServer", restartLanguageServers);
        registerCommand("applyFixes", applyFixes);
        registerCommand("showReferences", showReferences);
        registerCommand("runGlobalDiagnostics", runGlobalDiagnostics);

        hx = startHxLanguageServer();
        // hxml = startHxmlLanguageServer();
    }

    function registerCommand(command:String, callback:Function) {
        context.subscriptions.push(commands.registerCommand("haxe." + command, callback));
    }

    function applyFixes(uri:String, version:Int, edits:Array<TextEdit>) {
        var editor = window.activeTextEditor;
        if (editor == null || editor.document.uri.toString() != uri)
            return;

        // TODO:
        // if (editor.document.version != version) {
        //     window.showInformationMessage("Fix is outdated and cannot be applied to the document");
        //     return;
        // }

        editor.edit(function(mutator) {
            for (edit in edits) {
                var range = new Range(edit.range.start.line, edit.range.start.character, edit.range.end.line, edit.range.end.character);
                mutator.delete(range);
                mutator.insert(range.start, edit.newText);
            }
        });
    }

    function showReferences(uri:String, position:Position, locations:Array<Location>) {
        inline function copyPosition(position) return new Position(position.line, position.character);
        // this is retarded
        var locations = locations.map(function(location)
            return new Location(Uri.parse(cast location.uri), new Range(copyPosition(location.range.start), copyPosition(location.range.end)))
        );
        commands.executeCommand("editor.action.showReferences", Uri.parse(uri), copyPosition(position), locations).then(function(s) trace(s), function(s) trace("err: " + s));
    }

    function runGlobalDiagnostics() {
        hx.client.sendNotification({method: "vshaxe/runGlobalDiagnostics"});
    }

    function startHxLanguageServer() {
        var serverModule = context.asAbsolutePath("./server_wrapper.js");
        var serverOptions = {
            run: {module: serverModule, options: {env: js.Node.process.env}},
            debug: {module: serverModule, options: {env: js.Node.process.env, execArgv: ["--nolazy", "--debug=6004"]}}
        };
        var clientOptions = {
            documentSelector: "haxe",
            synchronize: {
                configurationSection: "haxe"
            },
            initializationOptions: {
                displayConfigurationIndex: displayConfig.getIndex()
            }
        };
        var hx = new ClientServer(context, new LanguageClient("haxe", "Haxe", serverOptions, clientOptions), "hx");
        hx.client.onReady().then(function(_) {
            displayConfig.onDidChangeIndex = function(index) {
                hx.client.sendNotification({method: "vshaxe/didChangeDisplayConfigurationIndex"}, {index: index});
            }
            context.subscriptions.push(hx.fileWatcher.onDidCreate(function(uri) {
                var editor = window.activeTextEditor;
                if (editor == null || editor.document.uri.fsPath != uri.fsPath)
                    return;
                if (editor.document.getText(new Range(0, 0, 0, 1)).length > 0) // skip non-empty created files (can be created by e.g. copy-pasting)
                    return;

                hx.client.sendRequest({method: "vshaxe/determinePackage"}, {fsPath: uri.fsPath}).then(function(result:{pack:String}) {
                    if (result.pack == "")
                        return;
                    editor.edit(function(edit) edit.insert(new Position(0, 0), 'package ${result.pack};\n'));
                });
            }));
        });
        return hx;
    }

    function startHxmlLanguageServer() {
        var serverModule = context.asAbsolutePath("./hxml_server_wrapper.js");
        var serverOptions = {
            run: {module: serverModule, options: {env: js.Node.process.env}},
            debug: {module: serverModule, options: {env: js.Node.process.env, execArgv: ["--nolazy", "--debug=6004"]}}
        };
        var clientOptions = {
            documentSelector: "hxml",
            synchronize: {
                configurationSection: "hxml"
            }
        };
        return new ClientServer(context, new LanguageClient("hxml", "HXML", serverOptions, clientOptions), "hxml");
    }

    function restartLanguageServers() {
        hx.stop(context);
        hx = startHxLanguageServer();
        // hxml.stop(context);
        // hxml = startHxmlLanguageServer();
    }

    @:keep
    @:expose("activate")
    static function main(context:ExtensionContext) {
        new Main(context);
    }
}
