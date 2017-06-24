package vshaxe;

import Vscode.*;
import vscode.*;
import js.RegExp;

class Main {
    function new(context:ExtensionContext) {
        new InitProject(context);
        var server = new LanguageServer(context);
        new Commands(context, server);

        setLanguageConfiguration();
        server.start();
    }

    function setLanguageConfiguration() {
        var defaultWordPattern = "(-?\\d*\\.\\d\\w*)|([^\\`\\~\\!\\@\\#\\%\\^\\&\\*\\(\\)\\-\\=\\+\\[\\{\\]\\}\\\\\\|\\;\\:\\'\\\"\\,\\.\\<\\>\\/\\?\\s]+)";
        var wordPattern = defaultWordPattern + "|(@:\\w*)"; // metadata
        languages.setLanguageConfiguration("haxe", {
            wordPattern: new RegExp(wordPattern),
            // based on https://github.com/Microsoft/vscode/blob/8d6645c/extensions/typescript/src/typescriptMain.ts#L285-L290
            indentationRules: {
                decreaseIndentPattern: new RegExp("^(.*\\*\\/)?\\s*[\\}|\\]|\\)].*$"),
                increaseIndentPattern: new RegExp("^.*(\\{[^}\"'`]*|\\([^)\"'`]*|\\[[^\\]\"'`]*)$"),
                indentNextLinePattern: new RegExp("(^\\s*(for|while|do|if|else|try|catch)|function)\\b(?!.*[;{}]\\s*(\\/\\/.*|\\/[*].*[*]\\/\\s*)?$)")
            }
        });
    }

    @:keep
    @:expose("activate")
    static function main(context:ExtensionContext) {
        new Main(context);
    }
}
