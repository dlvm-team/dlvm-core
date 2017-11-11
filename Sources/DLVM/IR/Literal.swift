//
//  Literal.swift
//  DLVM
//
//  Copyright 2016-2017 Richard Wei.
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

import CoreTensor
import CoreOp

/// Scalar or tensor literal, literally
/// - Note: It has no type or shape, because a `Literal` is not a `Value`.
/// But `LiteralValue`, that uses `Literal`, is a value.
public indirect enum Literal {
    public enum Scalar : Equatable {
        case int(IntegerLiteralType)
        case float(FloatLiteralType)
        case bool(BooleanLiteralType)
    }
    case undefined
    case null
    case zero
    case scalar(Scalar)
    case tensor([Use])
    case tuple([Use])
    case array([Use])
    case `struct`([(String, Use)])
}

extension Literal : Equatable {
    public static func == (lhs: Literal, rhs: Literal) -> Bool {
        switch (lhs, rhs) {
        case (.zero, .zero),
             (.undefined, .undefined),
             (.null, .null):
            return true
        case let (.scalar(s1), .scalar(s2)):
            return s1 == s2
        case let (.tensor(t1), .tensor(t2)):
            return t1 == t2
        case let (.tuple(tt1), .tuple(tt2)):
            return tt1 == tt2
        case let (.array(tt1), .array(tt2)):
            return tt1 == tt2
        case let (.struct(ss1), .struct(ss2)):
            return ss1.elementsEqual(ss2, by: { $0 == $1 })
        default: return false
        }
    }
}

public extension Literal.Scalar {
    var typeBase: DataType.Base {
        switch self {
        case .bool: return .bool
        case .int: return .int
        case .float: return .float
        }
    }
}

// MARK: - Literal conversion

extension Literal.Scalar : ExpressibleByIntegerLiteral {
    public init(integerLiteral value: IntegerLiteralType) {
        self = .int(value)
    }
}

extension Literal.Scalar : ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: BooleanLiteralType) {
        self = .bool(value)
    }
}

extension Literal.Scalar : ExpressibleByFloatLiteral {
    public init(floatLiteral value: FloatLiteralType) {
        self = .float(value)
    }
}

extension Literal : ExpressibleByIntegerLiteral {
    public init(integerLiteral value: IntegerLiteralType) {
        self = .scalar(Scalar(integerLiteral: value))
    }
}

extension Literal : ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: BooleanLiteralType) {
        self = .scalar(Scalar(booleanLiteral: value))
    }
}

extension Literal : ExpressibleByFloatLiteral {
    public init(floatLiteral value: FloatLiteralType) {
        self = .scalar(Scalar(floatLiteral: value))
    }
}

extension Literal : ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Use...) {
        self = .array(elements)
    }
}

extension Literal : ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, Use)...) {
        self = .struct(elements)
    }
}

extension Literal : ExpressibleByNilLiteral {
    public init(nilLiteral: ()) {
        self = .null
    }
}

// MARK: - Literal as value

/// Literal value. It wraps `Literal` into a value
public struct LiteralValue : Value {
    public var type: Type
    public var literal: Literal

    public init(type: Type, literal: Literal) {
        self.type = type
        self.literal = literal
    }

    public func makeUse() -> Use {
        return .literal(type, literal)
    }
}

extension LiteralValue : Equatable {
    public static func == (lhs: LiteralValue, rhs: LiteralValue) -> Bool {
        return lhs.type == rhs.type
            && lhs.literal == rhs.literal
    }
}

public extension Use {
    static func tensor(_ shape: TensorShape, _ dataType: DataType,
                       repeating item: Int) -> Use {
        let scalLit: Literal.Scalar
        switch dataType.base {
        case .int: scalLit = .int(item)
        case .float: scalLit = .float(Double(item))
        case .bool: scalLit = .bool(item == 0 ? false : true)
        }
        let lit: Literal = .scalar(scalLit)
        let type: Type = .tensor(shape, dataType)

        if shape.isScalar {
            return .literal(type, lit)
        } else {
            let subtensor = Use.tensor(shape.dropFirst(), dataType, repeating: item)
            let subtensors = Array(repeating: subtensor, count: shape[0])
            return .literal(type, .tensor(subtensors))
        }
    }
}

public extension DataType {
    func isExpressible(as scalar: Literal.Scalar) -> Bool {
        /// - TODO: Currently we are only checking type base,
        /// but we should really verify bit width as well
        switch (base, scalar) {
        case (.float, .float),
             (.float, .int),
             (.int, .int),
             (.bool, .bool):
            return true
        default:
            return false
        }
    }
}

public extension Literal {
    func substituting(_ new: Use, for old: Use) -> Literal {
        let condSubst = {$0 == old ? new : $0}
        switch self {
        case .array(let vv): return .array(vv.map(condSubst))
        case .tensor(let vv): return .tensor(vv.map(condSubst))
        case .tuple(let vv): return .tuple(vv.map(condSubst))
        case .struct(let fields):
            return .struct(Array(fields.map{($0.0, condSubst($0.1))}))
        case .null, .undefined, .zero, .scalar: return self
        }
    }

    var isZero: Bool {
        switch self {
        case .scalar(.int(0)), .scalar(.float(0)), .zero:
            return true
        default:
            return false
        }
    }

    var isOne: Bool {
        switch self {
        case .scalar(.int(1)), .scalar(.float(1)):
            return true
        default:
            return false
        }
    }

    var isScalar: Bool {
        guard case .scalar = self else { return false }
        return true
    }

    static func ~= (pattern: IntegerLiteralType, literal: Literal) -> Bool {
        switch literal {
        case .scalar(.int(pattern)):
            return true
        case let .scalar(.float(v)) where v == FloatLiteralType(pattern):
            return true
        case .zero where pattern == 0:
            return true
        default:
            return false
        }
    }
    
    static func ~= (pattern: FloatLiteralType, literal: Literal) -> Bool {
        switch (pattern, literal) {
        case (0.0, .zero): return true
        case (let v1, .scalar(.float(let v2))): return v1 == v2
        default: return false
        }
    }
}

public extension Use {
    private static func anyLiteral(from use: Use) -> Literal? {
        switch use {
        case let .literal(_, lit):
            return lit
        case let .instruction(_, inst):
            guard case let .literal(lit, _) = inst.kind else { return nil }
            return lit
        default:
            return nil
        }
    }
    
    static func ~= (pattern: IntegerLiteralType, use: Use) -> Bool {
        guard let lit = anyLiteral(from: use) else { return false }
        return pattern ~= lit
    }

    static func ~= (pattern: FloatLiteralType, use: Use) -> Bool {
        guard let lit = anyLiteral(from: use) else { return false }
        return pattern ~= lit
    }
}

public extension Value {
    /// Make a literal of the same type
    func makeLiteral(_ literal: Literal) -> LiteralValue {
        return LiteralValue(type: type, literal: literal)
    }

    /// Make a scalar literal of the same type, unless
    /// - Precondition: value type is tensor
    func makeScalar(_ scalar: Literal.Scalar) -> LiteralValue {
        guard case let .tensor(_, dtype) = type.canonical else {
            preconditionFailure("The type of \(self) is not tensor")
        }
        return LiteralValue(type: .scalar(dtype), literal: .scalar(scalar))
    }
}

public extension Use {
    func makeLiteral(_ literal: Literal) -> LiteralValue {
        return value.makeLiteral(literal)
    }

    func makeScalar(_ scalar: Literal.Scalar) -> LiteralValue {
        return value.makeScalar(scalar)
    }
}

// MARK: - Tensor to literal conversions
// WIP: rewrite using numeric protocols, may become deprecated

public extension TensorProtocol where UnitType == Int {
    func toLiteral() -> Literal {
        if shape.isScalar {
            return .scalar(.int(self.unit(at: 0)))
        } else {
            let type: Type = .tensor(shape, .int(UInt(Int.bitWidth)))
            let elementTensors: [Use] = map { .literal(type, $0.toLiteral()) }
            return .tensor(elementTensors)
        }
    }
}

public extension TensorProtocol where UnitType == Float {
    func toLiteral() -> Literal {
        if shape.isScalar {
            return .scalar(.float(Double(self.unit(at: 0))))
        } else {
            let type: Type = .tensor(shape, .float(.single))
            let elementTensors: [Use] = map { .literal(type, $0.toLiteral()) }
            return .tensor(elementTensors)
        }
    }
}

public extension TensorProtocol where UnitType == Double {
    func toLiteral() -> Literal {
        if shape.isScalar {
            return .scalar(.float(Double(self.unit(at: 0))))
        } else {
            let type: Type = .tensor(shape, .float(.double))
            let elementTensors: [Use] = map { .literal(type, $0.toLiteral()) }
            return .tensor(elementTensors)
        }
    }
}

public extension TensorProtocol where UnitType == BooleanLiteralType {
    func toLiteral() -> Literal {
        if shape.isScalar {
            return .scalar(.bool(self.unit(at: 0)))
        } else {
            let type: Type = .tensor(shape, .bool)
            let elementTensors: [Use] = map { .literal(type, $0.toLiteral()) }
            return .tensor(elementTensors)
        }
    }
}
