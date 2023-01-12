package vshaxe.tasks;

import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

import vshaxe.helper.PathHelper;

class CustomTaskProvider {
	static inline var TASK_NAME = "vshaxe-custom";
	static var problemMatcher = ~/^(\s*)(.+):(\d+): (?:lines \d+-(\d+)|character(?:s (\d+)-| )(\d+)) : (?:(Warning|Info) : )?(.*)$/;

	final taskConfiguration:TaskConfiguration;
	final hxmlDiscovery:HxmlDiscovery;
	final outputChannel:OutputChannel;

	public function new(taskConfiguration, hxmlDiscovery) {
		final collection = Vscode.languages.createDiagnosticCollection("haxe");
		outputChannel = Vscode.window.createOutputChannel(TASK_NAME);
		// outputChannel.show();

		Vscode.tasks.onDidEndTask(e -> {
			if (e.execution.task.definition.type == TASK_NAME) {
				// TODO: use workspaceFolders instead
				// TODO: make errors.log path configurable
				var path = Path.join([Vscode.workspace.rootPath, ".vscode", "errors.log"]);
				// var path = Path.join([Vscode.workspace.rootPath, ".vscode", "errors_manual.log"]);

				if (FileSystem.exists(path) && !FileSystem.isDirectory(path)) {
					collection.clear();
					final logs = File.getContent(path);
					final diagnostics:Map<String, Array<Diagnostic>> = [];
					var diagnostic = null;

					for (line in logs.split("\n")) {
						if (problemMatcher.match(line)) {
							// ~~TODO~~ also consider cases where we get a new top level error on a
							// position previously reported; in this case we want to add related
							// information instead of creating new diagnostic
							// => This seems to be fine, actually. Missing override keyword + wrong
							// signature generates two errors on the same position, and don't
							// conflict when problems are created like that.

							if (isEmpty(problemMatcher.matched(1))) {
								diagnostic = new Diagnostic(
									createRange(),
									problemMatcher.matched(8),
									// TODO (haxe compiler): add prefix to Info messages
									switch problemMatcher.matched(7) {
										case null | "": Error;
										case "Warning": Warning;
										case "Info": Information;
										case _: Error;
									}
								);

								final file = PathHelper.absolutize(problemMatcher.matched(2), Vscode.workspace.rootPath);
								if (!diagnostics.exists(file)) diagnostics.set(file, [diagnostic]);
								else diagnostics.get(file).push(diagnostic);
							} else {
								// TODO: handle diagnostic == null, which should not be possible
								final file = PathHelper.absolutize(problemMatcher.matched(2), Vscode.workspace.rootPath);
								final uri = Uri.file(file);

								// Add related info
								var rel = new DiagnosticRelatedInformation(
									new Location(uri, createRange()),
									problemMatcher.matched(8)
								);

								if (diagnostic.relatedInformation == null) diagnostic.relatedInformation = [rel];
								else diagnostic.relatedInformation.push(rel);
							}
						}
					}

					for (file in diagnostics.keys()) collection.set(Uri.file(file), diagnostics.get(file));

					// TODO: optionally(?) remove the log file
				}
			}
		});

		this.taskConfiguration = taskConfiguration;
		this.hxmlDiscovery = hxmlDiscovery;
		tasks.registerTaskProvider(TASK_NAME, this);
	}

	public function provideTasks(?token:CancellationToken):ProviderResult<Array<Task>> {
		return [
			for (file in hxmlDiscovery.files) {
				final definition:HaxeTaskDefinition = {
					type: TASK_NAME,
					file: file
				};
				// TODO: cleanup and factorize with the one in resolveTask below
				// TODO: make errors.log path configurable
				taskConfiguration.createTask(definition, 'custom ' + file, [
						// "--connect", "6000",
						file, "-D", "messages-log-file=.vscode/errors.log"
				]);
			}
		];
	}

	public function resolveTask(task:Task, ?token:CancellationToken):ProviderResult<Task> {
		// TODO: execute "normal" task with problem matcher (matching only top
		// level! so either "pretty" output or "diagnostics" output should be
		// used here) or manual problem matching depending on whether LSP
		// diagnostics are enabled or not
		// TODO: check haxe version here too; cannot work properly with a
		// version older than my error reporting PR
		outputChannel.appendLine("[resolveTask] diagnostics: " + Vscode.workspace.getConfiguration("haxe").get("enableDiagnostics"));

		var def:HaxeTaskDefinition = cast task.definition;
		var file = def.file;

		return taskConfiguration.createTask(def, 'custom ' + file, [file, "-D", "messages-log-file=.vscode/errors.log"]);
	}

	// TODO: clean that up..
	function createRange() {
		var line = Std.parseInt(problemMatcher.matched(3));
		var lineEnd = isEmpty(problemMatcher.matched(4)) ? line : Std.parseInt(problemMatcher.matched(4));

		// TODO: handle case where columns are not available
		var col = Std.parseInt(problemMatcher.matched(5));
		var colEnd = isEmpty(problemMatcher.matched(6)) ? col : Std.parseInt(problemMatcher.matched(6));

		// TODO: fix signature of overload, arguments seems to be in wrong order there
		return new Range(new Position(line-1, col-1), new Position(lineEnd-1, colEnd-1));
	}

	// TODO: use static extension
	function isEmpty(s:String) return s == null || s == "";
}

private typedef HaxeTaskDefinition = TaskDefinition & {file:String};
