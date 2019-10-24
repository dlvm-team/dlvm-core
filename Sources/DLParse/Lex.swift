//
//  Lex.swift
//  DLVM
//
//  Copyright 2016-2018 The DLVM Team.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import enum DLVM.InstructionKind
import enum DLVM.Opcode
import enum DLVM.DataType
import class DLVM.Function

// MARK: - Token definition

public enum Keyword {
    case module
    case stage, raw, optimizable
    case `struct`, `enum`, `case`, `func`, `var`, stack
    case type, opaque
    case at, to, from, by, upto, of
    case kernel, strides, leftDilation, rightDilation, groups
    case padding, none, half, full
    case then, `else`
    case wrt, keeping
    case void
    case zero, undefined, null
    case `true`, `false`
    case scalar
    case count
    case seedable
    case extern, adjoint
    case `init`, along, dims
}

public enum Punctuation {
    case leftParenthesis
    case rightParenthesis
    case leftSquareBracket
    case rightSquareBracket
    case leftAngleBracket
    case rightAngleBracket
    case leftCurlyBracket
    case rightCurlyBracket
    case colon
    case equal
    case rightArrow
    case comma
    case times
    case star
}

public enum IdentifierKind {
    case basicBlock
    case temporary
    case type
    case global
    case structKey
    case enumCase
}

public enum TokenKind : Equatable {
    case punctuation(Punctuation)
    case keyword(Keyword)
    case opcode(Opcode)
    case integer(IntegerLiteralType)
    case float(FloatLiteralType)
    case identifier(IdentifierKind, String)
    case anonymousGlobal(Int)
    case anonymousBasicBlock(Int)
    case anonymousArgument(Int, Int)
    case anonymousInstruction(Int, Int)
    case dataType(DataType)
    case stringLiteral(String)
    case attribute(Function.Attribute)
    case newLine
}

public extension TokenKind {
    func isIdentifier(ofKind kind: IdentifierKind) -> Bool {
        guard case .identifier(kind, _) = self else { return false }
        return true
    }

    var isOpcode: Bool {
        guard case .opcode(_) = self else { return false }
        return true
    }

    var isInteger: Bool {
        guard case .integer(_) = self else { return false }
        return true
    }

    var isFloat: Bool {
        guard case .float(_) = self else { return false }
        return true
    }
}

public struct Token {
    public var kind: TokenKind
    public var range: SourceRange
}

extension TokenKind {
    func makeToken(in range: SourceRange) -> Token {
        return Token(kind: self, range: range)
    }
}

public extension Token {
    var startLocation: SourceLocation {
        return range.lowerBound
    }

    var endLocation: SourceLocation {
        return range.upperBound
    }
}

// MARK: - Lexer interface

public class Lexer {
    fileprivate var characters: ArraySlice<UTF8.CodeUnit>
    fileprivate var location = SourceLocation()

    public init(text: String) {
        characters = ArraySlice(text.utf8)
    }
}

private extension Lexer {
    func advance(by n: Int) {
        characters.removeFirst(n)
        location.advance(by: n)
    }

    func advanceToNewLine() {
        characters.removeFirst()
        location.advanceToNewLine()
    }
}

// MARK: - UTF8 matching helpers

import class Foundation.NSRegularExpression
import struct Foundation.NSRange
import class Foundation.NSString

private extension ArraySlice where Element == UTF8.CodeUnit {
    static func ~= (pattern: String, value: ArraySlice<Element>) -> Bool {
        return pattern.utf8.elementsEqual(value)
    }

    func starts(with possiblePrefix: String) -> Bool {
        return starts(with: possiblePrefix.utf8)
    }

    var string: String {
        return withUnsafeBufferPointer { buffer in
            var scalars = String.UnicodeScalarView()
            for char in buffer {
                scalars.append(UnicodeScalar(char))
            }
            return String(scalars)
        }
    }

    func matchesRegex(_ regex: NSRegularExpression) -> Bool {
        let matches = regex.matches(in: string,
                                    options: [ .anchored ],
                                    range: NSRange(location: 0, length: count))
        return matches.count == 1 && matches[0].range.length == count
    }
}

private extension RangeReplaceableCollection where Element == UTF8.CodeUnit {
    mutating func append(_ string: StaticString) {
        string.withUTF8Buffer { buf in
            self.append(contentsOf: buf)
        }
    }
}

extension StaticString {
    static func ~= (pattern: StaticString, value: UTF8.CodeUnit) -> Bool {
        guard pattern.utf8CodeUnitCount == 1 else { return false }
        return pattern.utf8Start.pointee == value
    }

    static func ~= (pattern: StaticString, value: ArraySlice<UTF8.CodeUnit>) -> Bool {
        return pattern.withUTF8Buffer { ptr in
            ptr.elementsEqual(value)
        }
    }

    static func == (lhs: UTF8.CodeUnit?, rhs: StaticString) -> Bool {
        guard let lhs = lhs else { return false }
        return rhs.utf8CodeUnitCount == 1 && rhs.utf8Start.pointee == lhs
    }

    static func != (lhs: UTF8.CodeUnit?, rhs: StaticString) -> Bool {
        guard let lhs = lhs else { return true }
        return rhs.utf8CodeUnitCount != 1 || rhs.utf8Start.pointee != lhs
    }
}

private extension UTF8.CodeUnit {
    var isNewLine: Bool {
        switch self {
        case "\n", "\r": return true
        default: return false
        }
    }

    var isWhitespace: Bool {
        switch self {
        case " ", "\t": return true
        default: return false
        }
    }

    var isPunctuation: Bool {
        switch self {
        case 33...45, 58...64, 91...93, 123...126: return true
        default: return false
        }
    }

    var isDigit: Bool {
        switch self {
        case 48...57: return true
        default: return false
        }
    }

    var isAlphabet: Bool {
        switch self {
        case 65...90, 97...122: return true
        default: return false
        }
    }
}

// MARK: - Internal lexing routines

private let identifierPattern = try! NSRegularExpression(pattern: "[a-zA-Z_][a-zA-Z0-9_.]*",
                                                         options: [ .dotMatchesLineSeparators ])

private extension Lexer {
    func lexIdentifier(ofKind kind: IdentifierKind) throws -> Token {
        let prefix = characters.prefix(while: {
            !($0.isWhitespace || $0.isNewLine || $0.isPunctuation)
        })
        let startLoc = location
        advance(by: prefix.count)
        guard prefix.matchesRegex(identifierPattern) else {
            throw LexicalError.illegalIdentifier(startLoc..<location)
        }
        return Token(kind: .identifier(kind, prefix.string), range: startLoc..<location)
    }

    func scanPunctuation() throws -> Token {
        let startLoc = location
        let kind: TokenKind
        guard let first = characters.first else {
            preconditionFailure("Character stream is empty")
        }
        advance(by: 1)
        var count = 1
        switch first {
        case "(": kind = .punctuation(.leftParenthesis)
        case ")": kind = .punctuation(.rightParenthesis)
        case "[": kind = .punctuation(.leftSquareBracket)
        case "]": kind = .punctuation(.rightSquareBracket)
        case "<": kind = .punctuation(.leftAngleBracket)
        case ">": kind = .punctuation(.rightAngleBracket)
        case "{": kind = .punctuation(.leftCurlyBracket)
        case "}": kind = .punctuation(.rightCurlyBracket)
        case ":": kind = .punctuation(.colon)
        case "=": kind = .punctuation(.equal)
        case ",": kind = .punctuation(.comma)
        case "x": kind = .punctuation(.times)
        case "*": kind = .punctuation(.star)
        case "#": return try lexIdentifier(ofKind: .structKey)
        case "?": return try lexIdentifier(ofKind: .enumCase)
        case "!":
            let prefix = characters.prefix(while: {
                !($0.isWhitespace || $0.isNewLine || $0.isPunctuation)
            })
            advance(by: prefix.count)
            switch prefix {
            case "inline":
                kind = .attribute(.inline)
            default:
                throw LexicalError.unknownAttribute(startLoc..<location)
            }

        case "@":
            guard let nameStart = characters.first else {
                throw LexicalError.expectingIdentifierName(location)
            }
            /// If starting with a number, then it's an anonymous global identifier
            if nameStart.isDigit {
                let fst = characters.prefix(while: { $0.isDigit })
                advance(by: fst.count)
                guard let index = Int(fst.string) else {
                    throw LexicalError.invalidAnonymousIdentifierIndex(startLoc)
                }
                return Token(kind: .anonymousGlobal(index),
                             range: startLoc..<location)
            }
            /// Otherwise it's just a nominal identifier
            return try lexIdentifier(ofKind: .global)
        case "%":
            guard let nameStart = characters.first else {
                throw LexicalError.expectingIdentifierName(location)
            }
            /// If starting with a number, then it's an anonymous local identifier
            if nameStart.isDigit {
                let fst = characters.prefix(while: { $0.isDigit })
                advance(by: fst.count)
                guard let bbIndex = Int(fst.string) else {
                    throw LexicalError.invalidBasicBlockIndex(startLoc)
                }
                let sep = characters.first
                guard sep == "." || sep == "^" else {
                    throw LexicalError.invalidAnonymousLocalIdentifier(startLoc)
                }
                advance(by: 1)
                let snd = characters.prefix(while: { $0.isDigit })
                advance(by: snd.count)
                guard let localIndex = Int(snd.string) else {
                    throw LexicalError.invalidAnonymousIdentifierIndex(startLoc)
                }
                if sep == "." {
                    return Token(kind: .anonymousInstruction(bbIndex, localIndex),
                                 range: startLoc..<location)
                }
                return Token(kind: .anonymousArgument(bbIndex, localIndex),
                             range: startLoc..<location)
            }
            /// Otherwise it's just a nominal identifier
            return try lexIdentifier(ofKind: .temporary)
        case "$": return try lexIdentifier(ofKind: .type)
        case "'":
            guard let nameStart = characters.first else {
                throw LexicalError.expectingIdentifierName(location)
            }
            /// If starting with a number, then it's an anonymous basic block identifier
            if nameStart.isDigit {
                let fst = characters.prefix(while: { $0.isDigit })
                advance(by: fst.count)
                guard let index = Int(fst.string) else {
                    throw LexicalError.invalidAnonymousIdentifierIndex(startLoc)
                }
                return Token(kind: .anonymousBasicBlock(index),
                             range: startLoc..<location)
            }
            /// Otherwise it's just a nominal identifier
            return try lexIdentifier(ofKind: .basicBlock)
        case "\"":
            guard !characters.isEmpty else {
                /// EOF
                throw LexicalError.unclosedStringLiteral(startLoc..<location)
            }
            /// Character accumulator
            var chars: [UTF8.CodeUnit] = []
            /// Loop until we reach EOF or '"'
            while let current = characters.first, current != "\"" {
                switch current {
                /// Escape character
                case "\\":
                    count += 1
                    advance(by: 1)
                    guard let escaped = characters.first else {
                        throw LexicalError.unclosedStringLiteral(startLoc..<location)
                    }
                    switch escaped {
                    case "\"": chars.append("\"")
                    case "\\": chars.append("\\")
                    case "n": chars.append("\n")
                    case "t": chars.append("\t")
                    case "r": chars.append("\r")
                    default: throw LexicalError.invalidEscapeCharacter(escaped, location)
                    }
                /// New line
                case "\n", "\r":
                    throw LexicalError.unclosedStringLiteral(startLoc..<location)
                /// Normal character
                default:
                    chars.append(current)
                }
                count += 1
                advance(by: 1)
            }
            /// Check for end
            guard characters.first == "\"" else {
                throw LexicalError.unclosedStringLiteral(startLoc..<location)
            }
            /// Advance through '"'
            advance(by: 1)
            /// Append terminator because we are converting a C string
            chars.append("\0")
            kind = chars.withUnsafeBufferPointer { buffer in
                .stringLiteral(String(cString: buffer.baseAddress!))
            }
        case "-":
            guard let next = characters.first else {
                throw LexicalError.unexpectedToken(location)
            }
            /// If followed by ">", it's an arrow
            if next == ">" {
                count += 1
                advance(by: 1)
                kind = .punctuation(.rightArrow)
            }
            else if next.isDigit {
                var num = try scanNumber(isNegative: true)
                num.range = startLoc..<num.endLocation
                return num
            }
            else {
                throw LexicalError.unexpectedToken(location)
            }
        default:
            throw LexicalError.unexpectedToken(startLoc)
        }
        return Token(kind: kind, range: startLoc..<startLoc.advanced(by: count))
    }

    func scanNumber(isNegative: Bool = false) throws -> Token {
        let endOfWhole = characters.index(where: { !$0.isDigit }) ?? characters.endIndex
        var number = characters.prefix(upTo: endOfWhole)
        let startLoc = location
        advance(by: number.count)
        /// If there's a dot, lex float literal
        if endOfWhole < characters.endIndex, characters[endOfWhole] == "." {
            number.append(".")
            /// Has decimal dot
            let afterDot = characters.index(after: endOfWhole)
            advance(by: 1)
            guard afterDot < characters.endIndex, characters[afterDot].isDigit else {
                throw LexicalError.illegalNumber(startLoc..<location)
            }
            let decimal = characters.prefix(while: { $0.isDigit })
            advance(by: decimal.count)
            number.append(contentsOf: decimal)
            guard let float = FloatLiteralType(number.string) else {
                throw LexicalError.illegalNumber(startLoc..<location)
            }
            return Token(kind: .float(isNegative ? -float : float),
                         range: startLoc..<location)
        }
        /// Integer literal
        guard let integer = Int(number.string) else {
            throw LexicalError.illegalNumber(startLoc..<location)
        }
        return Token(kind: .integer(isNegative ? -integer : integer),
                     range: location..<location+characters.count)
    }

    func scanLetter() throws -> Token {
        let prefix = characters.prefix(while: {
            !($0.isWhitespace || $0.isNewLine || $0.isPunctuation)
        })
        let startLoc = location
        advance(by: prefix.count)
        let kind: TokenKind
        switch prefix {
        /// Keywords
        case "module": kind = .keyword(.module)
        case "stage": kind = .keyword(.stage)
        case "raw": kind = .keyword(.raw)
        case "optimizable": kind = .keyword(.optimizable)
        case "func": kind = .keyword(.`func`)
        case "struct": kind = .keyword(.`struct`)
        case "enum": kind = .keyword(.`enum`)
        case "case": kind = .keyword(.`case`)
        case "var": kind = .keyword(.`var`)
        case "type": kind = .keyword(.type)
        case "opaque": kind = .keyword(.opaque)
        case "at": kind = .keyword(.at)
        case "to": kind = .keyword(.to)
        case "upto": kind = .keyword(.upto)
        case "from": kind = .keyword(.from)
        case "by": kind = .keyword(.by)
        case "of": kind = .keyword(.of)
        case "then": kind = .keyword(.then)
        case "else": kind = .keyword(.`else`)
        case "kernel": kind = .keyword(.kernel)
        case "strides": kind = .keyword(.strides)
        case "leftDilation": kind = .keyword(.leftDilation)
        case "rightDilation": kind = .keyword(.rightDilation)
        case "groups": kind = .keyword(.groups)
        case "padding": kind = .keyword(.padding)
        case "none": kind = .keyword(.`none`)
        case "half": kind = .keyword(.half)
        case "full": kind = .keyword(.full)
        case "wrt": kind = .keyword(.wrt)
        case "keeping": kind = .keyword(.keeping)
        case "void": kind = .keyword(.void)
        case "zero": kind = .keyword(.zero)
        case "undefined": kind = .keyword(.undefined)
        case "null": kind = .keyword(.null)
        case "true": kind = .keyword(.true)
        case "false": kind = .keyword(.false)
        case "scalar": kind = .keyword(.scalar)
        case "count": kind = .keyword(.count)
        case "seedable": kind = .keyword(.seedable)
        case "extern": kind = .keyword(.extern)
        case "adjoint": kind = .keyword(.adjoint)
        case "init": kind = .keyword(.`init`)
        case "along": kind = .keyword(.along)
        case "dims": kind = .keyword(.dims)
        /// Opcode
        case "builtin": kind = .opcode(.builtin)
        case "literal": kind = .opcode(.literal)
        case "branch": kind = .opcode(.branch)
        case "conditional": kind = .opcode(.conditional)
        case "return": kind = .opcode(.`return`)
        case "dataTypeCast": kind = .opcode(.dataTypeCast)
        case "scan": kind = .opcode(.scan)
        case "reduce": kind = .opcode(.reduce)
        case "reduceWindow": kind = .opcode(.reduceWindow)
        case "dot": kind = .opcode(.dot)
        case "matrixMultiply": kind = .opcode(.dot) // TODO: Deprecated. Should emit warning
        case "concatenate": kind = .opcode(.concatenate)
        case "transpose": kind = .opcode(.transpose)
        case "reverse": kind = .opcode(.reverse)
        case "slice": kind = .opcode(.slice)
        case "convolve": kind = .opcode(.convolve)
        case "padShape": kind = .opcode(.padShape)
        case "squeezeShape": kind = .opcode(.squeezeShape)
        case "shapeCast": kind = .opcode(.shapeCast)
        case "bitCast": kind = .opcode(.bitCast)
        case "extract": kind = .opcode(.extract)
        case "insert": kind = .opcode(.insert)
        case "branchEnum": kind = .opcode(.branchEnum)
        case "apply": kind = .opcode(.apply)
        case "createStack": kind = .opcode(.createStack)
        case "destroyStack": kind = .opcode(.destroyStack)
        case "push": kind = .opcode(.push)
        case "pop": kind = .opcode(.pop)
        case "allocateStack": kind = .opcode(.allocateStack)
        case "allocateHeap": kind = .opcode(.allocateHeap)
        case "allocateBox": kind = .opcode(.allocateBox)
        case "projectBox": kind = .opcode(.projectBox)
        case "retain": kind = .opcode(.retain)
        case "release": kind = .opcode(.release)
        case "deallocate": kind = .opcode(.deallocate)
        case "load": kind = .opcode(.load)
        case "store": kind = .opcode(.store)
        case "elementPointer": kind = .opcode(.elementPointer)
        case "copy": kind = .opcode(.copy)
        case "trap": kind = .opcode(.trap)
        case "random": kind = .opcode(.random)
        case "select": kind = .opcode(.select)
        case "lessThan": kind = .opcode(.compare(.lessThan))
        case "lessThanOrEqual": kind = .opcode(.compare(.lessThanOrEqual))
        case "greaterThan": kind = .opcode(.compare(.greaterThan))
        case "greaterThanOrEqual": kind = .opcode(.compare(.greaterThanOrEqual))
        case "equal": kind = .opcode(.compare(.equal))
        case "notEqual": kind = .opcode(.compare(.notEqual))
        case "and": kind = .opcode(.booleanBinaryOp(.and))
        case "or": kind = .opcode(.booleanBinaryOp(.or))
        case "add": kind = .opcode(.numericBinaryOp(.add))
        case "subtract": kind = .opcode(.numericBinaryOp(.subtract))
        case "multiply": kind = .opcode(.numericBinaryOp(.multiply))
        case "divide": kind = .opcode(.numericBinaryOp(.divide))
        case "min": kind = .opcode(.numericBinaryOp(.min))
        case "max": kind = .opcode(.numericBinaryOp(.max))
        case "truncateDivide": kind = .opcode(.numericBinaryOp(.truncateDivide))
        case "floorDivide": kind = .opcode(.numericBinaryOp(.floorDivide))
        case "modulo": kind = .opcode(.numericBinaryOp(.modulo))
        case "power": kind = .opcode(.numericBinaryOp(.power))
        case "sinh": kind = .opcode(.numericUnaryOp(.sinh))
        case "cosh": kind = .opcode(.numericUnaryOp(.cosh))
        case "tanh": kind = .opcode(.numericUnaryOp(.tanh))
        case "log": kind = .opcode(.numericUnaryOp(.log))
        case "exp": kind = .opcode(.numericUnaryOp(.exp))
        case "negate": kind = .opcode(.numericUnaryOp(.negate))
        case "sign": kind = .opcode(.numericUnaryOp(.sign))
        case "square": kind = .opcode(.numericUnaryOp(.square))
        case "sqrt": kind = .opcode(.numericUnaryOp(.sqrt))
        case "round": kind = .opcode(.numericUnaryOp(.round))
        case "rsqrt": kind = .opcode(.numericUnaryOp(.rsqrt))
        case "ceil": kind = .opcode(.numericUnaryOp(.ceil))
        case "floor": kind = .opcode(.numericUnaryOp(.floor))
        case "tan": kind = .opcode(.numericUnaryOp(.tan))
        case "cos": kind = .opcode(.numericUnaryOp(.cos))
        case "sin": kind = .opcode(.numericUnaryOp(.sin))
        case "acos": kind = .opcode(.numericUnaryOp(.acos))
        case "asin": kind = .opcode(.numericUnaryOp(.asin))
        case "atan": kind = .opcode(.numericUnaryOp(.atan))
        case "lgamma": kind = .opcode(.numericUnaryOp(.lgamma))
        case "digamma": kind = .opcode(.numericUnaryOp(.digamma))
        case "erf": kind = .opcode(.numericUnaryOp(.erf))
        case "erfc": kind = .opcode(.numericUnaryOp(.erfc))
        case "rint": kind = .opcode(.numericUnaryOp(.rint))
        case "not": kind = .opcode(.not)
        /// Type-related
        case "x": kind = .punctuation(.times)
        case "f16": kind = .dataType(.float(.half))
        case "f32": kind = .dataType(.float(.single))
        case "f64": kind = .dataType(.float(.double))
        case "bool": kind = .dataType(.bool)
        case "stack": kind = .keyword(.stack)
        case _ where prefix.first == "i":
            let rest = prefix.dropFirst()
            guard rest.forAll({$0.isDigit}), let size = Int(rest.string) else {
                throw LexicalError.illegalNumber(startLoc+1..<location)
            }
            kind = .dataType(.int(UInt(size)))
        default:
            throw LexicalError.unexpectedToken(startLoc)
        }
        return Token(kind: kind, range: startLoc..<location)
    }

}

// MARK: - Lexing entry

public extension Lexer {
    /// Perform lexing on the input text
    /// - Returns: An array of tokens
    /// - Throws: `LexicalError` if lexing fails at any point
    func performLexing() throws -> [Token] {
        var tokens: [Token] = []
        while let first = characters.first {
            let startLoc = location
            let tok: Token
            /// Parse tokens starting with a punctuation
            if first.isPunctuation {
                tok = try scanPunctuation()
            }
            /// Parse tokens starting with a number
            else if first.isDigit {
                tok = try scanNumber()
            }
            /// Parse tokens starting with a letter
            else if first.isAlphabet {
                tok = try scanLetter()
            }
            /// Parse new line
            else if first.isNewLine {
                advanceToNewLine()
                tok = Token(kind: .newLine, range: startLoc..<startLoc+1)
            }
            /// Ignore whitespace
            else if first.isWhitespace {
                advance(by: 1)
                continue
            }
            /// Ignore line comment
            else if characters.starts(with: "//") {
                let comment = characters.prefix(while: { !$0.isNewLine })
                advance(by: comment.count)
                continue
            }
            /// Illegal start character
            else {
                throw LexicalError.unexpectedToken(location)
            }
            tokens.append(tok)
        }
        return tokens
    }
}
