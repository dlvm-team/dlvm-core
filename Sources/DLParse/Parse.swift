//
//  Parse.swift
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

/// This file contains a hand-written LL parser with reasonably fine-tuned
/// diagnostics. The parser entry is `Parser.parseModule`.

import CoreTensor
import DLVM

// MARK: - Semantic environment

private struct Environment {
    var locals: [String : Value] = [:]
    var globals: [String : Value] = [:]
    var nominalTypes: [String : Type] = [:]
    var basicBlocks: [String : BasicBlock] = [:]
    var processedBasicBlocks: Set<BasicBlock> = []
    var processedFunctions: Set<Function> = []
}

// MARK: - Parser interface

public class Parser {
    public let tokens: [Token]
    fileprivate lazy var restTokens: ArraySlice<Token> = ArraySlice(self.tokens)
    fileprivate var environment = Environment()

    public init(tokens: [Token]) {
        self.tokens = tokens
    }

    public convenience init(text: String) throws {
        let lexer = Lexer(text: text)
        self.init(tokens: try lexer.performLexing())
    }
}

// MARK: - Common routines and combinators

private extension Parser {
    var currentToken: Token? {
        guard let first = restTokens.first else { return nil }
        return first
    }

    var nextToken: Token? {
        return restTokens.dropFirst().first
    }

    var currentLocation: SourceLocation? {
        return currentToken?.range.lowerBound
    }

    var isEOF: Bool {
        return restTokens.isEmpty
    }

    @discardableResult
    func consumeToken() -> Token {
        return restTokens.removeFirst()
    }

    func consume(if predicate: (TokenKind) throws -> Bool) rethrows {
        guard let token = currentToken else { return }
        if try predicate(token.kind) {
            consumeToken()
        }
    }

    func consume(while predicate: (TokenKind) throws -> Bool) rethrows {
        while let first = currentToken, try predicate(first.kind) {
            consumeToken()
        }
    }

    @discardableResult
    func consumeIfAny(_ tokenKind: TokenKind) -> Token? {
        if let tok = currentToken, tok.kind == tokenKind {
            return restTokens.removeFirst()
        }
        return nil
    }

    @discardableResult
    func consume(_ tokenKind: TokenKind) throws -> Token {
        guard let first = restTokens.first else {
            throw ParseError.unexpectedEndOfInput(expected: String(describing: tokenKind))
        }
        guard first.kind == tokenKind else {
            throw ParseError.unexpectedToken(expected: String(describing: tokenKind), first)
        }
        return restTokens.removeFirst()
    }

    @discardableResult
    func consumeOrDiagnose(_ expected: String) throws -> Token {
        guard currentToken != nil else {
            throw ParseError.unexpectedEndOfInput(expected: expected)
        }
        return consumeToken()
    }

    @discardableResult
    func withPeekedToken<T>(_ expected: String, _ execute: (Token) throws -> T?) throws -> T {
        let tok = try peekOrDiagnose(expected)
        guard let result = try execute(tok) else {
            throw ParseError.unexpectedToken(expected: expected, tok)
        }
        return result
    }

    @discardableResult
    func peekOrDiagnose(_ expected: String) throws -> Token {
        guard let tok = currentToken else {
            throw ParseError.unexpectedEndOfInput(expected: expected)
        }
        return tok
    }

    func parseInteger() throws -> (Int, SourceRange) {
        let name: String = "an integer"
        let tok = try consumeOrDiagnose(name)
        switch tok.kind {
        case let .integer(i): return (i, tok.range)
        default: throw ParseError.unexpectedToken(expected: name, tok)
        }
    }

    func parseBool() throws -> (Bool, SourceRange) {
        let name: String = "a bool"
        let tok = try consumeOrDiagnose(name)
        switch tok.kind {
        case .keyword(.true): return (true, tok.range)
        case .keyword(.false): return (false, tok.range)
        default: throw ParseError.unexpectedToken(expected: name, tok)
        }
    }

    func parsePadding() throws -> (Padding, SourceRange) {
        let name: String = "a padding type"
        let tok = try consumeOrDiagnose(name)
        switch tok.kind {
        case .keyword(.none): return (.none, tok.range)
        case .keyword(.half): return (.half, tok.range)
        case .keyword(.full): return (.full, tok.range)
        default: throw ParseError.unexpectedToken(expected: name, tok)
        }
    }

    func parseDataType() throws -> (DataType, SourceRange) {
        let name: String = "a data type"
        let tok = try consumeOrDiagnose(name)
        switch tok.kind {
        case let .dataType(dt): return (dt, tok.range)
        default: throw ParseError.unexpectedToken(expected: name, tok)
        }
    }

    func parseIdentifier(
        ofKind kind: IdentifierKind, isDefinition: Bool = false
    ) throws -> (String, Token) {
        let tok = try consumeOrDiagnose("an identifier")
        let name: String
        switch tok.kind {
        case .identifier(kind, let id): name = id
        default: throw ParseError.unexpectedIdentifierKind(kind, tok)
        }
        /// If we are parsing a name definition, check for its uniqueness
        let contains: (String) -> Bool
        switch kind {
        case .basicBlock: contains = environment.basicBlocks.keys.contains
        case .global: contains = environment.globals.keys.contains
        case .temporary: contains = environment.locals.keys.contains
        case .type: contains = environment.nominalTypes.keys.contains
        default: return (name, tok)
        }
        if isDefinition && contains(name) {
            throw ParseError.redefinedIdentifier(tok)
        }
        return (name, tok)
    }

    @discardableResult
    func withBacktracking<T>(_ execute: () throws -> T?) rethrows -> T? {
        let originalTokens = restTokens
        guard let result = try execute() else {
            restTokens = originalTokens
            return nil
        }
        return result
    }

    func withPreservedState(execute: () throws -> ()) {
        let originalTokens = restTokens
        _ = try? execute()
        restTokens = originalTokens
    }

    @discardableResult
    func consumeWrappablePunctuation(_ punct: Punctuation) throws -> Token {
        consumeAnyNewLines()
        let tok = try consume(.punctuation(punct))
        consumeAnyNewLines()
        return tok
    }

    func consumeStringLiteral() throws -> (String, SourceRange) {
        let tok = try consumeOrDiagnose("a string literal")
        guard case let .stringLiteral(str) = tok.kind else {
            throw ParseError.unexpectedToken(expected: "a string literal", tok)
        }
        return (str, tok.range)
    }

    func consumeAnyNewLines() {
        consume(while: {$0 == .newLine})
    }

    func consumeOneOrMore(_ kind: TokenKind) throws {
        try consume(kind)
        consume(while: { $0 == kind })
    }

    /// Parse one or more with optional backtracking
    /// - Note: In the closure, return `nil` to backtrack
    private func parseMany<T>(_ parseElement: () throws -> T?) rethrows -> [T] {
        var elements: [T] = []
        while let result = try withBacktracking(parseElement) {
            elements.append(result)
        }
        return elements
    }

    /// Parse one or more with optional backtracking
    /// - Note: In the first closure, return `nil` to backtrack
    func parseMany<T>(
        _ parseElement: () throws -> T?, unless: ((Token) -> Bool)? = nil,
        separatedBy parseSeparator: () throws -> ()
    ) rethrows -> [T] {
        guard let tok = currentToken else { return [] }
        if let unless = unless, unless(tok) { return [] }
        guard let first = try withBacktracking(parseElement) else { return [] }
        var elements: [T] = []
        while let _ = withBacktracking({ try? parseSeparator() }),
            let result = try withBacktracking(parseElement) {
            elements.append(result)
        }
        return [first] + elements
    }
}

// MARK: - Recursive descent cases

extension Parser {
    /// Parse uses separated by ','
    func parseUseList(
        in basicBlock: BasicBlock?, unless: ((Token) -> Bool)? = nil
    ) throws -> [Use] {
        return try parseMany({ try parseUse(in: basicBlock).0 },
                             unless: unless,
                             separatedBy: { try self.consumeWrappablePunctuation(.comma) })
    }

    /// Parse a literal
    func parseLiteral(in basicBlock: BasicBlock?) throws -> (Literal, SourceRange) {
        let tok = try consumeOrDiagnose("a literal")
        switch tok.kind {
        /// Float
        case let .float(f):
            return (.scalar(.float(f)), tok.range)
        /// Integer
        case let .integer(i):
            return (.scalar(.int(i)), tok.range)
        /// Boolean `true`
        case .keyword(.true):
            return (.scalar(.bool(true)), tok.range)
        /// Boolean `false`
        case .keyword(.false):
            return (.scalar(.bool(false)), tok.range)
        /// `null`
        case .keyword(.null):
            return (.null, tok.range)
        /// `undefined`
        case .keyword(.undefined):
            return (.undefined, tok.range)
        /// `zero`
        case .keyword(.zero):
            return (.zero, tok.range)
        /// Array
        case .punctuation(.leftSquareBracket):
            let elements = try parseUseList(in: basicBlock,
                                            unless: { $0.kind == .punctuation(.rightSquareBracket) })
            try consumeWrappablePunctuation(.rightSquareBracket)
            return (.array(elements), tok.range)
        /// Tuple
        case .punctuation(.leftParenthesis):
            let elements = try parseUseList(in: basicBlock,
                                            unless: { $0.kind == .punctuation(.rightParenthesis) })
            try consumeWrappablePunctuation(.rightParenthesis)
            return (.tuple(elements), tok.range)
        /// Tensor
        case .punctuation(.leftAngleBracket):
            let elements = try parseUseList(in: basicBlock,
                                            unless: { $0.kind == .punctuation(.rightAngleBracket) })
            try consumeWrappablePunctuation(.rightAngleBracket)
            return (.tensor(elements), tok.range)
        /// Struct
        case .punctuation(.leftCurlyBracket):
            let fields: [(String, Use)] = try parseMany({
                let (key, _) = try parseIdentifier(ofKind: .structKey)
                try consumeWrappablePunctuation(.equal)
                let (val, _) = try parseUse(in: basicBlock)
                return (key, val)
            }, unless: { tok in
                tok.kind == .punctuation(.rightCurlyBracket)
            }, separatedBy: {
                try self.consumeWrappablePunctuation(.comma)
            })
            let rightBkt = try consumeWrappablePunctuation(.rightCurlyBracket)
            return (.struct(fields), tok.startLocation..<rightBkt.endLocation)
        /// Enum
        case .identifier(.enumCase, let name):
            try consumeWrappablePunctuation(.leftParenthesis)
            let associatedValues: [Use] = try parseUseList(
                in: basicBlock,
                unless: { $0.kind == .punctuation(.rightParenthesis)}
            )
            let rightPrn = try consumeWrappablePunctuation(.rightParenthesis)
            return (.enumCase(name, associatedValues), tok.startLocation..<rightPrn.endLocation)
        default:
            throw ParseError.unexpectedToken(expected: "a literal", tok)
        }
    }

    /// Parse a non-scalar shape
    func parseNonScalarShape() throws -> (TensorShape, SourceRange) {
        let (first, firstRange) = try parseInteger()
        var dims = [first]
        var lastLoc = firstRange.upperBound
        while let dim: Int = withBacktracking({
            let num: Int, range: SourceRange
            do {
                try consumeWrappablePunctuation(.times)
                (num, range) = try parseInteger()
            } catch {
                return nil
            }
            lastLoc = range.upperBound
            return num
        }) { dims.append(dim) }
        return (TensorShape(dims), firstRange.lowerBound..<lastLoc)
    }

    /// Parse an integer list
    func parseIntegerList() throws -> [Int] {
        return try parseMany({
            try parseInteger().0
        }, separatedBy: {
            try consumeWrappablePunctuation(.comma)
        })
    }

    /// Parse a list of integer tuples
    func parseIntegerTupleList() throws -> [(Int, Int)] {
        return try parseMany({
            try consume(.punctuation(.leftParenthesis))
            let first = try parseInteger().0
            try consume(.punctuation(.comma))
            let second = try parseInteger().0
            try consume(.punctuation(.rightParenthesis))
            return (first, second)
        }, separatedBy: {
            try consumeWrappablePunctuation(.comma)
        })
    }

    /// Parse a shape
    func parseShape() throws -> TensorShape {
        return try withPeekedToken("""
            dimensions separated by 'x', or 'scalar'
            """, { tok in
                switch tok.kind {
                case .keyword(.scalar):
                    consumeToken()
                    return .scalar
                case .integer(_):
                    return try parseNonScalarShape().0
                default:
                    return nil
                }
            }
        )
    }

    func parseReductionCombinator(in basicBlock: BasicBlock?) throws -> ReductionCombinator {
        return try withPeekedToken("""
            a function or an associative operator
            """, { tok in
                switch tok.kind {
                case .opcode(.builtin):
                    consumeToken()
                    let (opcode, range) = try consumeStringLiteral()
                    guard let intrinsic = IntrinsicRegistry.global.intrinsic(named: opcode) else {
                        throw ParseError.undefinedIntrinsic(opcode, range)
                    }
                    guard let numericBuiltin = intrinsic as? NumericBinaryIntrinsic.Type else {
                        throw ParseError.invalidReductionCombinator(intrinsic, range)
                    }
                    return .numericBuiltin(numericBuiltin)
                case .identifier(_):
                    return try .function(parseUse(in: basicBlock).0)
                case .opcode(.numericBinaryOp(let op)):
                    consumeToken()
                    return .numeric(op)
                case .opcode(.booleanBinaryOp(let op)):
                    consumeToken()
                    return .boolean(op)
                default:
                    return nil
                }
            }
        )
    }

    func parseElementKey(in basicBlock: BasicBlock?) throws -> (ElementKey, SourceRange) {
        return try withPeekedToken("an element key", { tok in
            consumeToken()
            switch tok.kind {
            case let .integer(i):
                return (.index(i), tok.range)
            case let .identifier(.structKey, nameKey):
                return (.name(nameKey), tok.range)
            default:
                let (val, range) = try parseUse(in: basicBlock)
                return (.value(val), range)
            }
        })
    }

    func parseType() throws -> (Type, SourceRange) {
        let tok = try consumeOrDiagnose("a type")
        switch tok.kind {
        /// Void
        case .keyword(.void):
            return (.void, tok.range)
        /// Scalar
        case .dataType(let dt):
            return (.tensor([], dt), tok.range)
        /// Stack
        case .keyword(.stack):
            return (.stack, tok.range)
        /// Array
        case .punctuation(.leftSquareBracket):
            let (count, _) = try parseInteger()
            try consumeWrappablePunctuation(.times)
            let (elementType, _) = try parseType()
            let rightBkt = try consume(.punctuation(.rightSquareBracket))
            return (.array(count, elementType), tok.startLocation..<rightBkt.endLocation)
        /// Tensor
        case .punctuation(.leftAngleBracket):
            let (shape, _) = try parseNonScalarShape()
            try consumeWrappablePunctuation(.times)
            let (dt, _) = try parseDataType()
            let rightBkt = try consume(.punctuation(.rightAngleBracket))
            return (.tensor(shape, dt), tok.startLocation..<rightBkt.endLocation)
        /// Tuple/function
        case .punctuation(.leftParenthesis):
            let elementTypes = try parseMany({
                try parseType().0
            }, unless: { tok in
                tok.kind == .punctuation(.rightParenthesis)
            }, separatedBy: {
                try self.consumeWrappablePunctuation(.comma)
            })
            let rightPrn = try consume(.punctuation(.rightParenthesis))
            /// Check for any hint of function type
            if let tok = withBacktracking({try? consumeWrappablePunctuation(.rightArrow)}) {
                let (retType, retRange) = try parseType()
                return (.function(elementTypes, retType), tok.startLocation..<retRange.upperBound)
            }
            return (.tuple(elementTypes), tok.startLocation..<rightPrn.endLocation)
        /// Nominal type
        case .identifier(.type, let typeName):
            guard let type = environment.nominalTypes[typeName] else {
                throw ParseError.undefinedNominalType(tok)
            }
            return (type, tok.range)
        /// Pointer
        case .punctuation(.star):
            let (pointeeType, range) = try parseType()
            return (.pointer(pointeeType), tok.startLocation..<range.upperBound)
        default:
            throw ParseError.unexpectedToken(expected: "a type", tok)
        }
    }

    func parseTypeList() throws -> [Type] {
        try consume(.punctuation(.leftParenthesis))
        return try parseMany({
            let (type, _) = try parseType()
            return type
        }, unless: { tok in
            tok.kind == .punctuation(.rightParenthesis)
        }, separatedBy: {
            try self.consumeWrappablePunctuation(.comma)
        })
    }

    func parseTypeSignature() throws -> (Type, SourceRange) {
        try consume(.punctuation(.colon))
        consumeAnyNewLines()
        return try parseType()
    }

    func parseUse(in basicBlock: BasicBlock?) throws -> (Use, SourceRange) {
        let tok = try peekOrDiagnose("a use of value")
        let use: Use
        let range: SourceRange
        switch tok.kind {
        /// Identifier
        case let .identifier(kind, id):
            consumeToken()
            /// Either a global or a local
            let maybeVal: Value?
            switch kind {
            case .global: maybeVal = environment.globals[id]
            case .temporary: maybeVal = environment.locals[id]
            default: throw ParseError.unexpectedIdentifierKind(kind, tok)
            }
            guard let val = maybeVal else {
                throw ParseError.undefinedIdentifier(tok)
            }
            use = val.makeUse()
            let (type, typeSigRange) = try parseTypeSignature()
            range = tok.startLocation..<typeSigRange.upperBound
            /// Verify that computed and parsed types match.
            guard type == use.type else {
                throw ParseError.typeMismatch(expected: use.type, range)
            }
        /// Anonymous global identifier
        case let .anonymousGlobal(index):
            guard let bb = basicBlock else {
                throw ParseError.anonymousIdentifierNotInLocal(tok)
            }
            consumeToken()
            let module = bb.parent.parent
            if index < module.variables.count {
                let variable = module.variables[index]
                use = %variable
            } else {
                let funcIndex = index - module.variables.count
                let function = module[funcIndex]
                use = %function
            }
            let (type, typeSigRange) = try parseTypeSignature()
            range = tok.startLocation..<typeSigRange.upperBound
            guard type == use.type else {
                throw ParseError.typeMismatch(expected: use.type, range)
            }
        /// Anonymous instruction in a basic block
        case let .anonymousInstruction(bbIndex, instIndex):
            guard let bb = basicBlock else {
                throw ParseError.anonymousIdentifierNotInLocal(tok)
            }
            consumeToken()
            let function = bb.parent
            /// Criteria for identifier index:
            /// - BB referred to must precede the current BB
            /// - Instruction referred to must precede the current instruction
            guard bbIndex <= function.endIndex else {
                throw ParseError.invalidInstructionIndex(tok)
            }
            let refBB = bbIndex == function.endIndex ? bb : function[bbIndex]
            guard refBB.indices.contains(instIndex) else {
                throw ParseError.invalidInstructionIndex(tok)
            }
            let inst = refBB[instIndex]
            /// This value cannot be named, or have void type
            guard inst.name == nil, inst.type != .void else {
                throw ParseError.undefinedIdentifier(tok)
            }
            /// Now we can use this value
            use = %inst
            let (type, typeSigRange) = try parseTypeSignature()
            range = tok.startLocation..<typeSigRange.upperBound
            guard type == use.type else {
                throw ParseError.typeMismatch(expected: use.type, range)
            }
        /// Anonymous argument in a basic block
        case let .anonymousArgument(bbIndex, argIndex):
            guard let bb = basicBlock else {
                throw ParseError.anonymousIdentifierNotInLocal(tok)
            }
            consumeToken()
            let function = bb.parent
            /// Criteria for identifier index:
            /// - BB referred to must precede the current BB
            guard bbIndex <= function.endIndex else {
                throw ParseError.invalidArgumentIndex(tok)
            }
            let refBB = bbIndex == function.endIndex ? bb : function[bbIndex]
            guard refBB.arguments.indices.contains(argIndex) else {
                throw ParseError.invalidArgumentIndex(tok)
            }
            let arg = refBB.arguments[argIndex]
            /// This value cannot be named, or have void type
            guard arg.name == nil, arg.type != .void else {
                throw ParseError.undefinedIdentifier(tok)
            }
            /// Now we can use this value
            use = %arg
            let (type, typeSigRange) = try parseTypeSignature()
            range = tok.startLocation..<typeSigRange.upperBound
            guard type == use.type else {
                throw ParseError.typeMismatch(expected: use.type, range)
            }
        /// Literal
        case .float(_), .integer(_), .keyword(.true), .keyword(.false),
             .punctuation(.leftAngleBracket),
             .punctuation(.leftCurlyBracket),
             .punctuation(.leftSquareBracket),
             .punctuation(.leftParenthesis):
            let (lit, _) = try parseLiteral(in: basicBlock)
            let (type, typeSigRange) = try parseTypeSignature()
            range = tok.startLocation..<typeSigRange.upperBound
            use = .literal(type, lit)
        default:
            throw ParseError.unexpectedToken(expected: "a use of value", tok)
        }
        return (use, range)
    }

    func parseInstructionKind(in basicBlock: BasicBlock?) throws -> InstructionKind {
        let opcode: Opcode = try withPeekedToken("an opcode") { tok in
            guard case let .opcode(opcode) = tok.kind else {
                return nil
            }
            consumeToken()
            return opcode
        }
        switch opcode {
        /// 'builtin' "<op>" '(' (<val> (',' <val>)*)? ')'
        case .builtin:
            let (opcode, range) = try consumeStringLiteral()
            guard let intrinsic = IntrinsicRegistry.global.intrinsic(named: opcode) else {
                throw ParseError.undefinedIntrinsic(opcode, range)
            }
            try consume(.punctuation(.leftParenthesis))
            let args = try parseUseList(in: basicBlock,
                                        unless: { $0.kind == .punctuation(.rightParenthesis) })
            try consume(.punctuation(.rightParenthesis))
            try consume(.punctuation(.rightArrow))
            let (allegedType, typeRange) = try parseType()
            let resultType = intrinsic.resultType(for: args)
            guard allegedType == resultType else {
                throw ParseError.typeMismatch(expected: resultType, typeRange)
            }
            return .builtin(intrinsic, args)

        /// 'literal' <literal> ':' <type>
        case .literal:
            let (lit, _) = try parseLiteral(in: basicBlock)
            let (type, _) = try parseTypeSignature()
            return .literal(lit, type)

        /// 'branch' <bb> '(' (<val> (',' <val>)*)? ')'
        case .branch:
            let bbTok = try consumeOrDiagnose("a basic block identifier")
            let bbName: String
            switch bbTok.kind {
            case let .identifier(.basicBlock, name):
                bbName = name
            case let .anonymousBasicBlock(index):
                bbName = String(index)
            default:
                throw ParseError.unexpectedToken(expected: "a basic block identifier", bbTok)
            }
            guard let bb = environment.basicBlocks[bbName] else {
                throw ParseError.undefinedIdentifier(bbTok)
            }
            try consume(.punctuation(.leftParenthesis))
            let args = try parseUseList(in: basicBlock,
                                        unless: { $0.kind == .punctuation(.rightParenthesis) })
            try consume(.punctuation(.rightParenthesis))
            return .branch(bb, args)

        /// 'conditional' <cond> 'then' <bb> '(' (<val> (',' <val>)*)? ')'
        ///                      'else' <bb> '(' (<val> (',' <val>)*)? ')'
        case .conditional:
            let (cond, _) = try parseUse(in: basicBlock)
            /// Then
            try consume(.keyword(.then))
            let thenBBTok = try consumeOrDiagnose("a basic block identifier")
            let thenBBName: String
            switch thenBBTok.kind {
            case let .identifier(.basicBlock, name):
                thenBBName = name
            case let .anonymousBasicBlock(index):
                thenBBName = String(index)
            default:
                throw ParseError.unexpectedToken(expected: "a basic block identifier", thenBBTok)
            }
            guard let thenBB = environment.basicBlocks[thenBBName] else {
                throw ParseError.undefinedIdentifier(thenBBTok)
            }
            try consume(.punctuation(.leftParenthesis))
            let thenArgs = try parseUseList(in: basicBlock,
                                            unless: { $0.kind == .punctuation(.rightParenthesis) })
            try consume(.punctuation(.rightParenthesis))
            /// Else
            try consume(.keyword(.else))
            let elseBBTok = try consumeOrDiagnose("a basic block identifier")
            let elseBBName: String
            switch elseBBTok.kind {
            case let .identifier(.basicBlock, name):
                elseBBName = name
            case let .anonymousBasicBlock(index):
                elseBBName = String(index)
            default:
                throw ParseError.unexpectedToken(expected: "a basic block identifier", elseBBTok)
            }
            guard let elseBB = environment.basicBlocks[elseBBName] else {
                throw ParseError.undefinedIdentifier(elseBBTok)
            }
            try consume(.punctuation(.leftParenthesis))
            let elseArgs = try parseUseList(in: basicBlock,
                                            unless: { $0.kind == .punctuation(.rightParenthesis) })
            try consume(.punctuation(.rightParenthesis))
            return .conditional(cond, thenBB, thenArgs, elseBB, elseArgs)

        /// 'return' <val>?
        case .return:
            if case .newLine? = currentToken?.kind {
                return .return(nil)
            }
            let (val, range) = try parseUse(in: basicBlock)
            guard let returnType = basicBlock?.parent.returnType else {
                throw ParseError.notInBasicBlock(range)
            }
            guard val.type == returnType else {
                throw ParseError.typeMismatch(expected: returnType, range)
            }
            return .return(val)

        /// 'dataTypeCast' <val> 'to' <data_type>
        case .dataTypeCast:
            let (srcVal, _) = try parseUse(in: basicBlock)
            try consume(.keyword(.to))
            let (dtype, _) = try parseDataType()
            return .dataTypeCast(srcVal, dtype)

        /// 'scan' <val> 'by' <func|assoc_op> 'along' <num> (',' <num>)*
        case .scan:
            let (val, _) = try parseUse(in: basicBlock)
            try consume(.keyword(.by))
            let combinator = try parseReductionCombinator(in: basicBlock)
            try consume(.keyword(.along))
            let dims = try parseIntegerList()
            return .scan(combinator, val, dims: dims)

        /// 'reduce' <val> 'by' <func|assoc_op> 'init' <val> 'along' <num> (',' <num>)*
        case .reduce:
            let (val, _) = try parseUse(in: basicBlock)
            try consume(.keyword(.by))
            let combinator = try parseReductionCombinator(in: basicBlock)
            try consume(.keyword(.`init`))
            let (initial, _) = try parseUse(in: basicBlock)
            try consume(.keyword(.along))
            let dims = try parseIntegerList()
            return .reduce(combinator, val, initial: initial, dims: dims)

        /// 'reduceWindow' <val> 'by' <func|assoc_op> 'init' <val>
        ///     'dims' <num> (',' <num>)*
        ///     'strides' <num> (',' <num>)*
        ///     'padding' <bool>
        case .reduceWindow:
            let (val, _) = try parseUse(in: basicBlock)
            try consume(.keyword(.by))
            let combinator = try parseReductionCombinator(in: basicBlock)
            try consume(.keyword(.`init`))
            let (initial, _) = try parseUse(in: basicBlock)
            try consume(.keyword(.dims))
            let dims = try parseIntegerList()
            try consume(.keyword(.strides))
            let strides = try parseIntegerList()
            try consume(.keyword(.padding))
            let padding = try parsePadding().0
            return .reduceWindow(combinator, val, initial: initial, dims: dims,
                                 strides: strides, padding: padding)

        /// 'dot' <val> ',' <val>
        case .dot:
            let (lhs, _) = try parseUse(in: basicBlock)
            try consumeWrappablePunctuation(.comma)
            let (rhs, _) = try parseUse(in: basicBlock)
            return .dot(lhs, rhs)

        /// 'concatenate' <val> (',' <val>)* along <num>
        case .concatenate:
            let vals = try parseUseList(in: basicBlock)
            try consume(.keyword(.along))
            let (axis, _) = try parseInteger()
            return .concatenate(vals, axis: axis)

        /// 'transpose' <val>
        case .transpose:
            return try .transpose(parseUse(in: basicBlock).0)

        /// 'reverse' <val> 'along' <num> (',' <num>)*
        case .reverse:
            let val = try parseUse(in: basicBlock).0
            try consume(.keyword(.along))
            let dims = try parseIntegerList()
            return .reverse(val, dims: dims)

        /// 'slice' <val> 'from' <num> 'upto' <num>
        case .slice:
            let (val, _) = try parseUse(in: basicBlock)
            try consume(.keyword(.from))
            let (lowerBound, _) = try parseInteger()
            try consume(.keyword(.upto))
            let (upperBound, _) = try parseInteger()
            return .slice(val, at: lowerBound...upperBound)

        /// 'convolve' <val> 'kernel' <val>
        ///     'strides' <num> (',' <num>)*
        ///     'padding' '(' <num> ',' <num> ')' (',' '(' <num> ',' <num> ')')*
        ///     'leftDilation' <num> (',' <num>)*
        ///     'rightDilation' <num> (',' <num>)*
        ///     'groups' <num>
        case .convolve:
            let (val, _) = try parseUse(in: basicBlock)
            try consume(.keyword(.kernel))
            let (kernel, _) = try parseUse(in: basicBlock)
            /// strides
            var strides: [Int]?
            if case .keyword(.strides)? = currentToken?.kind {
                consumeToken()
                strides = try parseIntegerList()
            }
            /// padding
            var padding: [(low: Int, high: Int)]?
            if case .keyword(.padding)? = currentToken?.kind {
                consumeToken()
                padding = try parseIntegerTupleList()
            }
            /// left dilation
            var ld: [Int]?
            if case .keyword(.leftDilation)? = currentToken?.kind {
                consumeToken()
                ld = try parseIntegerList()
            }
            /// right dilation
            var rd: [Int]?
            if case .keyword(.rightDilation)? = currentToken?.kind {
                consumeToken()
                rd = try parseIntegerList()
            }
            /// groups
            var groups: Int?
            if case .keyword(.groups)? = currentToken?.kind {
                consumeToken()
                groups = try parseInteger().0
            }
            return .convolve(val, kernel: kernel, strides: strides, padding: padding,
                             leftDilation: ld, rightDilation: rd, groups: groups)

        /// 'rank' 'of' <val>
        case .rank:
            try consume(.keyword(.of))
            let (val, _) = try parseUse(in: basicBlock)
            return .rank(of: val)

        /// 'shape' 'of' <val>
        case .shape:
            try consume(.keyword(.of))
            let (val, _) = try parseUse(in: basicBlock)
            return .shape(of: val)

        /// 'unitCount' 'of' <val>
        case .unitCount:
            try consume(.keyword(.of))
            let (val, _) = try parseUse(in: basicBlock)
            return .unitCount(of: val)

        /// 'padShape' <val> 'at' <num>
        case .padShape:
            let (val, _) = try parseUse(in: basicBlock)
            try consume(.keyword(.at))
            let (index, _) = try parseInteger()
            return .padShape(val, at: index)

        /// 'squeezeShape' <val> 'at' <num>
        case .squeezeShape:
            let (val, _) = try parseUse(in: basicBlock)
            try consume(.keyword(.at))
            let (index, _) = try parseInteger()
            return .squeezeShape(val, at: index)

        /// 'shapeCast' <val> 'to' <shape>
        case .shapeCast:
            let (val, _) = try parseUse(in: basicBlock)
            try consume(.keyword(.to))
            let shape = try parseShape()
            return .shapeCast(val, to: shape)

        /// 'bitCast' <val> 'to' <type>
        case .bitCast:
            let (val, _) = try parseUse(in: basicBlock)
            try consume(.keyword(.to))
            let (type, _) = try parseType()
            return .bitCast(val, to: type)

        /// 'extract' <num|key|val> (',' <num|key|val>)* 'from' <val>
        case .extract:
            let keys: [ElementKey] = try parseMany({
                try parseElementKey(in: basicBlock).0
            }, separatedBy: {
                try consumeWrappablePunctuation(.comma)
            })
            try consume(.keyword(.from))
            return .extract(from: try parseUse(in: basicBlock).0, at: keys)

        /// 'insert' <val> 'to' <val> 'at' <num|key|val> (',' <num|key|val>)*
        case .insert:
            let (srcVal, _) = try parseUse(in: basicBlock)
            try consume(.keyword(.to))
            let (destVal, _) = try parseUse(in: basicBlock)
            try consume(.keyword(.at))
            let keys: [ElementKey] = try parseMany({
                try parseElementKey(in: basicBlock).0
            }, separatedBy: {
                try consumeWrappablePunctuation(.comma)
            })
            return .insert(srcVal, to: destVal, at: keys)

        /// 'branchEnum' <val> ('case' <enum_case> <bb>)*
        case .branchEnum:
            let (enumCase, _) = try parseUse(in: basicBlock)
            let branches: [(String, BasicBlock)] = try parseMany({
                if currentToken?.kind == .newLine {
                    return nil
                }
                try consume(.keyword(.case))
                let caseName = try parseIdentifier(ofKind: .enumCase).0
                let bbTok = try consumeOrDiagnose("a basic block identifier")
                let bbName: String
                switch bbTok.kind {
                case let .identifier(.basicBlock, name):
                    bbName = name
                case let .anonymousBasicBlock(index):
                    bbName = String(index)
                default:
                    throw ParseError.unexpectedToken(expected: "a basic block identifier", bbTok)
                }
                guard let bb = environment.basicBlocks[bbName] else {
                    throw ParseError.undefinedIdentifier(bbTok)
                }
                return (caseName, bb)
            })
            return .branchEnum(enumCase, branches)

        /// 'apply' <val> '(' <val>+ ')'
        case .apply:
            return try withPeekedToken("a function identifier") { tok in
                let kind: IdentifierKind
                let name: String
                switch tok.kind {
                case let .identifier(funcKind, funcName):
                    kind = funcKind
                    name = funcName
                case let .anonymousGlobal(index):
                    kind = .global
                    name = String(index)
                default:
                    return nil
                }
                consumeToken()
                let fn: Value
                switch kind {
                case .global:
                    guard let val = environment.globals[name] else { return nil }
                    fn = val
                case .temporary:
                    guard let val = environment.locals[name] else { return nil }
                    fn = val
                default:
                    return nil
                }
                try consume(.punctuation(.leftParenthesis))
                let args = try parseUseList(in: basicBlock,
                                            unless: { $0.kind == .punctuation(.rightParenthesis) })
                try consume(.punctuation(.rightParenthesis))
                try consume(.punctuation(.rightArrow))
                guard case let .function(_, retType) = fn.type.canonical else {
                    throw ParseError.notFunctionType(tok.range)
                }
                let (parsedRetType, typeSigRange) = try parseType()
                guard parsedRetType == retType else {
                    throw ParseError.typeMismatch(expected: retType, typeSigRange)
                }
                return .apply(fn.makeUse(), args)
            }

        /// 'allocateStack' <type> 'count' <num>
        case .allocateStack:
            let (type, _) = try parseType()
            try consume(.keyword(.count))
            let (count, _) = try parseInteger()
            return .allocateStack(type, count)

        /// 'allocateHeap' <type> 'count' <val>
        case .allocateHeap:
            let (type, _) = try parseType()
            try consume(.keyword(.count))
            let (count, _) = try parseUse(in: basicBlock)
            return .allocateHeap(type, count: count)

        /// 'allocateBox' <type>
        case .allocateBox:
            return try .allocateBox(parseType().0)

        /// 'projectBox' <val>
        case .projectBox:
            return try .projectBox(parseUse(in: basicBlock).0)

        /// 'createStack'
        case .createStack:
            return .createStack

        /// 'destroyStack' <val>
        case .destroyStack:
            let (stack, _) = try parseUse(in: basicBlock)
            return .destroyStack(stack)

        /// 'push' <val> 'to' <val>
        case .push:
            let (val, _) = try parseUse(in: basicBlock)
            try consume(.keyword(.to))
            let (stack, _) = try parseUse(in: basicBlock)
            return .push(val, to: stack)

        /// 'pop' <type> 'from' <val>
        case .pop:
            let (ty, _) = try parseType()
            try consume(.keyword(.from))
            let (stack, _) = try parseUse(in: basicBlock)
            return .pop(ty, from: stack)

        /// 'retain' <val>
        case .retain:
            return try .retain(parseUse(in: basicBlock).0)

        /// 'release' <val>
        case .release:
            return try .release(parseUse(in: basicBlock).0)

        /// 'deallocate' <val>
        case .deallocate:
            return try .deallocate(parseUse(in: basicBlock).0)

        /// 'load' <val>
        case .load:
            return try .load(parseUse(in: basicBlock).0)

        /// 'store' <val> 'to' <val>
        case .store:
            let (src, _) = try parseUse(in: basicBlock)
            try consume(.keyword(.to))
            let (dest, _) = try parseUse(in: basicBlock)
            return .store(src, to: dest)

        /// 'elementPointer' <val> 'at' <num|key|val> (<num|key|val> ',')*
        case .elementPointer:
            let (base, _) = try parseUse(in: basicBlock)
            try consume(.keyword(.at))
            let keys: [ElementKey] = try parseMany({
                try parseElementKey(in: basicBlock).0
            }, separatedBy: {
                try consumeWrappablePunctuation(.comma)
            })
            return .elementPointer(base, keys)

        /// 'copy' 'from' <val> 'to' <val> 'count' <val>
        case .copy:
            try consume(.keyword(.from))
            let (src, _) = try parseUse(in: basicBlock)
            try consume(.keyword(.to))
            let (dest, _) = try parseUse(in: basicBlock)
            try consume(.keyword(.count))
            let (count, _) = try parseUse(in: basicBlock)
            return .copy(from: src, to: dest, count: count)

        /// 'trap'
        case .trap:
            return .trap

        /// <numeric_binary_op> <val>, <val>
        case let .numericBinaryOp(op):
            let (lhs, _) = try parseUse(in: basicBlock)
            try consumeWrappablePunctuation(.comma)
            let (rhs, _) = try parseUse(in: basicBlock)
            return .numericBinary(op, lhs, rhs)

        /// <boolean_binary_op> <val>, <val>
        case let .booleanBinaryOp(op):
            let (lhs, _) = try parseUse(in: basicBlock)
            try consumeWrappablePunctuation(.comma)
            let (rhs, _) = try parseUse(in: basicBlock)
            return .booleanBinary(op, lhs, rhs)

        /// <comparison_op> <val>, <val>
        case let .compare(op):
            let (lhs, _) = try parseUse(in: basicBlock)
            try consumeWrappablePunctuation(.comma)
            let (rhs, _) = try parseUse(in: basicBlock)
            return .compare(op, lhs, rhs)

        /// <numeric_unary_op> <val>
        case let .numericUnaryOp(op):
            return try .numericUnary(op, parseUse(in: basicBlock).0)

        case .not:
            return try .not(parseUse(in: basicBlock).0)

        /// 'random' <shape> 'from' <val> 'upto' <val>
        case .random:
            let shape = try parseShape()
            try consume(.keyword(.from))
            let (lo, _) = try parseUse(in: basicBlock)
            try consume(.keyword(.upto))
            let (hi, _) = try parseUse(in: basicBlock)
            return .random(shape, from: lo, upTo: hi)

        /// 'select' <val>, <val> 'by' <val>
        case .select:
            let (lhs, _) = try parseUse(in: basicBlock)
            try consumeWrappablePunctuation(.comma)
            let (rhs, _) = try parseUse(in: basicBlock)
            try consume(.keyword(.by))
            let (flags, _) = try parseUse(in: basicBlock)
            return .select(lhs, rhs, by: flags)
        }
    }

    func parseInstruction(in basicBlock: BasicBlock) throws -> Instruction? {
        guard let tok = currentToken else { return nil }
        func parseKind(isNamed: Bool) throws -> InstructionKind {
            let kind = try parseInstructionKind(in: basicBlock)
            let type = kind.type
            /// If instruction kind gives invalid result, operands must be wrong.
            guard type != .invalid else {
                throw ParseError.invalidOperands(tok, kind.opcode)
            }
            /// Cannot have void type.
            if isNamed, type == .void {
                throw ParseError.cannotNameVoidValue(tok)
            }
            return kind
        }
        switch tok.kind {
        case let .identifier(.temporary, name):
            consumeToken()
            try consumeWrappablePunctuation(.equal)
            let kind = try parseKind(isNamed: true)
            guard !environment.locals.keys.contains(name) else {
                throw ParseError.redefinedIdentifier(tok)
            }
            let inst = Instruction(name: name, kind: kind, parent: basicBlock)
            environment.locals[name] = inst
            return inst
        case let .anonymousInstruction(bbIndex, instIndex):
            /// Check BB index and instruction index
            /// - BB index must equal the current BB index
            /// - Instruction index must equal the next instruction index,
            ///   i.e. the current instruction count
            guard bbIndex == basicBlock.parent.count, // BB hasn't been added to function
                instIndex == basicBlock.endIndex // Inst hasn't been added to BB
                else { throw ParseError.invalidInstructionIndex(tok) }
            consumeToken()
            try consumeWrappablePunctuation(.equal)
            let kind = try parseKind(isNamed: true)
            return Instruction(kind: kind, parent: basicBlock)
        case .opcode(_):
            return Instruction(kind: try parseKind(isNamed: false), parent: basicBlock)
        default:
            return nil
        }
    }

    func parseArgumentList() throws -> [(String, Type)] {
        return try parseMany({
            let (name, _) = try parseIdentifier(ofKind: .temporary, isDefinition: true)
            let (type, _) = try parseTypeSignature()
            return (name, type)
        }, unless: { tok in
            tok.kind == .punctuation(.rightParenthesis)
        }, separatedBy: {
            try self.consumeWrappablePunctuation(.comma)
        })
    }

    func parseBasicBlock(in function: Function) throws -> BasicBlock? {
        /// Parse basic block header.
        guard let nameTok = currentToken else { return nil }
        let name: String
        switch nameTok.kind {
        case let .identifier(.basicBlock, bbName):
            name = bbName
        case let .anonymousBasicBlock(index):
            /// Check basic block index
            /// - bb index must equal the next bb index,
            ///   i.e. the current bb count.
            guard index == function.count
                else { throw ParseError.invalidBasicBlockIndex(nameTok) }
            name = String(index)
        case .punctuation(.rightCurlyBracket):
            return nil
        default:
            throw ParseError.unexpectedToken(expected: "a basic block identifier", nameTok)
        }
        consumeToken()
        try consumeWrappablePunctuation(.leftParenthesis)
        let args = try parseArgumentList()
        try consumeWrappablePunctuation(.rightParenthesis)
        try consume(.punctuation(.colon))
        try consumeOneOrMore(.newLine)
        /// Retrieve previously added BB during scanning.
        guard let bb = environment.basicBlocks[name] else {
            preconditionFailure("""
                Basic block should have been added during the symbol scanning \
                stage
                """)
        }
        /// Check if this prototype is already processed. If so, it's a
        /// redefinition of this BB.
        guard !environment.processedBasicBlocks.contains(bb) else {
            throw ParseError.redefinedIdentifier(nameTok)
        }
        /// Add to the set of processed basic blocks.
        environment.processedBasicBlocks.insert(bb)
        /// Parse BB's formal arguments.
        for (name, type) in args {
            let arg = Argument(name: name, type: type, parent: bb)
            bb.arguments.append(arg)
            /// Insert arguments into symbol table.
            if let name = arg.name {
                environment.locals[name] = arg
            }
        }
        /// Parse instructions.
        while let inst = try parseInstruction(in: bb) {
            bb.append(inst)
            try consumeOneOrMore(.newLine)
        }
        return bb
    }

    func parseFunctionDeclarationKind() throws -> Function.DeclarationKind {
        return try withPeekedToken("a declaration kind ('extern' or 'adjoint')", { tok in
            switch tok.kind {
            case .keyword(.adjoint):
                consumeToken()
                let fnName: String
                let tok = try consumeOrDiagnose("a function identifier")
                switch tok.kind {
                case let .identifier(.global, name):
                    fnName = name
                case let .anonymousGlobal(index):
                    fnName = String(index)
                default:
                    return nil
                }
                guard let fn = environment.globals[fnName] as? Function else {
                    throw ParseError.undefinedIdentifier(tok)
                }
                /// from
                var sourceIndex: Int?
                if case .keyword(.from)? = currentToken?.kind {
                    consumeToken()
                    sourceIndex = try parseInteger().0
                }
                /// wrt
                var argumentIndices: [Int]?
                if case .keyword(.wrt)? = currentToken?.kind {
                    consumeToken()
                    argumentIndices = try parseMany({
                        try parseInteger().0
                    }, separatedBy: {
                        try consume(.punctuation(.comma))
                    })
                }
                /// keeping
                var keptIndices: [Int] = []
                if case .keyword(.keeping)? = currentToken?.kind {
                    consumeToken()
                    keptIndices = try parseMany({
                        try parseInteger().0
                    }, separatedBy: {
                        try consume(.punctuation(.comma))
                    })
                }
                /// seedable
                var isSeedable = false
                if case .keyword(.seedable)? = currentToken?.kind {
                    consumeToken()
                    isSeedable = true
                }
                let config = AdjointConfiguration(
                    primal: fn, sourceIndex: sourceIndex,
                    argumentIndices: argumentIndices, keptIndices: keptIndices,
                    isSeedable: isSeedable
                )
                return .adjoint(config)

            case .keyword(.extern):
                consumeToken()
                return .external
            default:
                return nil
            }
        })
    }

    func parseFunction(in module: Module) throws -> Function {
        /// Parse attributes.
        var attributes: Set<Function.Attribute> = []
        while case let .attribute(attr)? = currentToken?.kind {
            attributes.insert(attr)
            consumeToken()
            try consumeOneOrMore(.newLine)
        }
        /// Parse declaration kind.
        var declKind: Function.DeclarationKind?
        if case .punctuation(.leftSquareBracket)? = currentToken?.kind {
            consumeToken()
            declKind = try parseFunctionDeclarationKind()
            try consume(.punctuation(.rightSquareBracket))
            try consumeOneOrMore(.newLine)
        }
        /// Parse main function declaration/definition.
        let funcTok = try consume(.keyword(.func))
        let nameTok = try consumeOrDiagnose("a function identifier")
        let name: String
        switch nameTok.kind {
        case let .identifier(.global, funcName):
            name = funcName
        case let .anonymousGlobal(index):
            /// Check global index
            /// - Function index must equal the next function index,
            ///   i.e. the sum of current variable and function counts
            guard index == module.variables.count + module.count
                else { throw ParseError.invalidFunctionIndex(nameTok) }
            name = String(index)
        default:
            throw ParseError.unexpectedToken(expected: "a function identifier", nameTok)
        }
        let (type, typeSigRange) = try parseTypeSignature()
        /// Verify that the type signature is a function type.
        guard case let .function(args, ret) = type.canonical else {
            throw ParseError.notFunctionType(typeSigRange)
        }
        /// Retrieve previous added function during scanning.
        guard let function = environment.globals[name] as? Function else {
            preconditionFailure("""
                Function should have been added during the symbol scanning stage
                """)
        }
        /// Check if this prototype is already processed. If so, it's a redefinition
        /// of this function.
        guard !environment.processedFunctions.contains(function) else {
            throw ParseError.redefinedIdentifier(nameTok)
        }
        /// Insert this function to the set of processed functions.
        environment.processedFunctions.insert(function)
        /// Complete function's properties.
        function.declarationKind = declKind
        function.argumentTypes = args
        function.returnType = ret
        function.attributes = attributes
        /// Scan basic block symbols and create prototypes in the symbol table.
        withPreservedState {
            while restTokens.count >= 2 {
                let start = restTokens.startIndex
                let (tok0, tok1) = (restTokens[start], restTokens[start+1])
                /// End of function, break
                if tok0.kind == .punctuation(.rightCurlyBracket) { break }
                let name: String
                var isAnonymous = false
                switch (tok0.kind, tok1.kind) {
                case let (.newLine, .identifier(.basicBlock, bbName)):
                    name = bbName
                case let (.newLine, .anonymousBasicBlock(index)):
                    name = String(index)
                    isAnonymous = true
                default:
                    consumeToken()
                    continue
                }
                restTokens.removeFirst(2)
                let proto = BasicBlock(name: isAnonymous ? nil : name,
                                       arguments: [], parent: function)
                environment.basicBlocks[name] = proto
            }
        }
        /// Parse definition in `{...}` when it's not a declaration.
        if function.isDefinition {
            consumeAnyNewLines()
            try consume(.punctuation(.leftCurlyBracket))
            try consumeOneOrMore(.newLine)
            while let bb = try parseBasicBlock(in: function) {
                function.append(bb)
            }
            try consume(.punctuation(.rightCurlyBracket))
        }
        /// Otherwise if `{` follows the declaration, emit proper diagnostics.
        else if let tok = currentToken, tok.kind == .punctuation(.leftCurlyBracket) {
            throw ParseError.declarationCannotHaveBody(
                declaration: funcTok.startLocation..<typeSigRange.upperBound,
                body: tok
            )
        }
        /// Clear function-local mappings from the symbol table.
        environment.basicBlocks.removeAll()
        environment.locals.removeAll()
        environment.processedBasicBlocks.removeAll()
        return function
    }

    func parseVariable(in module: Module) throws -> Variable {
        try consume(.keyword(.var))
        let tok = try consumeOrDiagnose("a variable identifier")
        /// Variable must be declared before all functions.
        guard module.isEmpty else {
            throw ParseError.variableAfterFunction(tok)
        }
        let name: String
        var isAnonymous = false
        switch tok.kind {
        case let .identifier(.global, varName):
            name = varName
        case let .anonymousGlobal(index):
            /// Check global index
            /// - Variable index must equal the next variable index,
            ///   i.e. the current variable count
            guard index == module.variables.count // Variable hasn't been added to module
                else { throw ParseError.invalidVariableIndex(tok) }
            name = String(index)
            isAnonymous = true
        default:
            throw ParseError.unexpectedToken(expected: "a variable identifier", tok)
        }
        let (type, _) = try parseTypeSignature()
        let variable = Variable(name: isAnonymous ? nil : name,
                                valueType: type, parent: module)
        environment.globals[name] = variable
        return variable
    }

    func parseTypeAlias(in module: Module, isDefinition: Bool = true) throws -> TypeAlias {
        try consume(.keyword(.type))
        let (name, _) = try parseIdentifier(ofKind: .type,
                                            isDefinition: isDefinition)
        try consumeWrappablePunctuation(.equal)
        let type: Type? = try withPeekedToken("a type") { tok in
            switch tok.kind {
            case .keyword(.opaque):
                consumeToken()
                return nil as Type?
            default:
                return try parseType().0
            }
        }
        let alias = TypeAlias(name: name, type: type)
        environment.nominalTypes[name] = .alias(alias)
        return alias
    }

    func parseStruct(in module: Module, isDefinition: Bool = true) throws -> StructType {
        try consume(.keyword(.struct))
        let (name, _) = try parseIdentifier(ofKind: .type,
                                            isDefinition: isDefinition)
        try consumeWrappablePunctuation(.leftCurlyBracket)
        let fields: [StructType.Field] = try parseMany({
            if currentToken?.kind == .punctuation(.rightCurlyBracket) {
                return nil
            }
            let (name, _) = try parseIdentifier(ofKind: .structKey)
            let (type, _) = try parseTypeSignature()
            return (name: name, type: type)
        }, separatedBy: {
            try consumeOneOrMore(.newLine)
        })
        consumeAnyNewLines()
        try consume(.punctuation(.rightCurlyBracket))
        let structTy = StructType(name: name, fields: fields)
        environment.nominalTypes[name] = .struct(structTy)
        return structTy
    }

    func parseEnum(in module: Module, isDefinition: Bool = true) throws -> EnumType {
        try consume(.keyword(.enum))
        let (name, _) = try parseIdentifier(ofKind: .type,
                                            isDefinition: isDefinition)
        let enumTy = EnumType(name: name, cases: [])
        environment.nominalTypes[name] = .enum(enumTy)
        try consumeWrappablePunctuation(.leftCurlyBracket)
        let cases: [EnumType.Case] = try parseMany({
            if currentToken?.kind == .punctuation(.rightCurlyBracket) {
                return nil
            }
            let (name, _) = try parseIdentifier(ofKind: .enumCase)
            try consume(.punctuation(.leftParenthesis))
            let types = try parseMany({
                try parseType().0
            }, unless: {
                $0.kind == .punctuation(.rightParenthesis)
            }, separatedBy: {
                try consume(.punctuation(.comma))
            })
            try consume(.punctuation(.rightParenthesis))
            return (name: name, associatedTypes: types)
        }, separatedBy: {
            try consumeOneOrMore(.newLine)
        })
        consumeAnyNewLines()
        try consume(.punctuation(.rightCurlyBracket))
        cases.forEach{enumTy.append($0)}
        return enumTy
    }
}

// MARK: - Parser entry

public extension Parser {
    /// Parser entry
    func parseModule() throws -> Module {
        consumeAnyNewLines()
        try consume(.keyword(.module))
        let (name, _) = try consumeStringLiteral()
        /// Stage
        try consumeOneOrMore(.newLine)
        try consume(.keyword(.stage))
        let stage: Module.Stage = try withPeekedToken("'raw' or 'optimizable'", { tok in
            switch tok.kind {
            case .keyword(.raw):
                consumeToken()
                return .raw
            case .keyword(.optimizable):
                consumeToken()
                return .optimizable
            default: return nil
            }
        })
        let module = Module(name: name, stage: stage)

        /// Scan nominal types and store in environment.
        withPreservedState {
            while let tok = currentToken {
                switch tok.kind {
                case .keyword(.type):
                    let type = try parseTypeAlias(in: module)
                    module.typeAliases.append(type)

                case .keyword(.struct):
                    let structure = try parseStruct(in: module)
                    module.structs.append(structure)

                case .keyword(.enum):
                    let enumeration = try parseEnum(in: module)
                    module.enums.append(enumeration)

                default: consumeToken()
                }
            }
        }

        /// Scan function symbols and create prototypes in the symbol table.
        withPreservedState {
            while restTokens.count >= 3 {
                let start = restTokens.startIndex
                let (tok0, tok1, tok2) = (restTokens[start], restTokens[start+1], restTokens[start+2])
                let name: String
                var isAnonymous = false
                switch (tok0.kind, tok1.kind, tok2.kind) {
                case let (.newLine, .keyword(.func), .identifier(.global, funcName)):
                    name = funcName
                case let (.newLine, .keyword(.func), .anonymousGlobal(index)):
                    name = String(index)
                    isAnonymous = true
                default:
                    consumeToken()
                    continue
                }
                restTokens.removeFirst(3)
                let (type, typeSigRange) = try parseTypeSignature()
                /// Verify that the type signature is a function type.
                guard case let .function(argTypes, retType) = type.canonical else {
                    throw ParseError.notFunctionType(typeSigRange)
                }
                let proto = Function(name: isAnonymous ? nil : name,
                                     argumentTypes: argTypes,
                                     returnType: retType, parent: module)
                environment.globals[name] = proto
            }
        }

        try consumeOneOrMore(.newLine)
        /// Parse top-level declarations/definitions.
        while let tok = currentToken {
            switch tok.kind {
            case .keyword(.type):
                guard module.isEmpty, module.variables.isEmpty else {
                    throw ParseError.typeDeclarationNotBeforeValues(tok)
                }
                _ = try parseTypeAlias(in: module, isDefinition: false)

            case .keyword(.struct):
                guard module.isEmpty, module.variables.isEmpty else {
                    throw ParseError.typeDeclarationNotBeforeValues(tok)
                }
                _ = try parseStruct(in: module, isDefinition: false)

            case .keyword(.enum):
                guard module.isEmpty, module.variables.isEmpty else {
                    throw ParseError.typeDeclarationNotBeforeValues(tok)
                }
                _ = try parseEnum(in: module, isDefinition: false)

            case .keyword(.func), .attribute(_), .punctuation(.leftSquareBracket):
                let fn = try parseFunction(in: module)
                module.append(fn)

            case .keyword(.var):
                let variable = try parseVariable(in: module)
                module.variables.append(variable)

            default:
                throw ParseError.unexpectedToken(
                    expected: "a type alias, a struct, an enum, a global variable, or a function", tok
                )
            }
            if isEOF { break }
            try consumeOneOrMore(.newLine)
        }

        /// ... end of input
        return module
    }
}
