//
//  CommandInterpreter.swift
//  Zphyr
//
//  Detects spoken meta-commands in the transcript (e.g. "annule" / "cancel that",
//  "copie dans le presse-papiers" / "copy to clipboard").
//  Currently a stub -- expand as the command vocabulary grows.
//
// TODO: [COMMANDS] Implement full spoken command grammar:
//   - "annule" / "cancel that" -> discard last insertion
//   - "copie" / "copy that" -> copy without inserting
//   - "formate en liste" / "make a list" -> force list mode
//   - "nouveau paragraphe" / "new paragraph" -> inject \n\n
//   For complex commands, consider a lightweight keyword-tree parser.

import Foundation

enum RecognizedCommand: Equatable {
    case none
    case cancelLast
    case copyOnly
    case forceList
    case newParagraph
    case customAction(String)
}

struct CommandInterpreter {
    static let shared = CommandInterpreter()

    /// Scans the transcript for a known command prefix/suffix.
    /// Returns (.none, fullText) if no command is found.
    /// Returns (command, remainingText) if a command is detected and stripped.
    func interpret(_ transcript: String, languageCode: String) -> (command: RecognizedCommand, cleanedText: String) {
        // TODO: implement command detection
        return (.none, transcript)
    }
}
