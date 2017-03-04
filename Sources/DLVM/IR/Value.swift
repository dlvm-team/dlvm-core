//
//  Value.swift
//  DLVM
//
//  Created by Richard Wei on 1/10/17.
//
//

/// Scope of value
public enum Scope {
    case global
    case local
    case none
}

/// Value base
public protocol Value {
    var shape: TensorShape { get }
    var type: DataType { get }
    static var scope: Scope { get }
}

/// Scalar or tensor literal, literally
/// - Note: It has no type or shape, because a `Literal` is not a `Value`.
/// But `LiteralValue`, that uses `Literal`, is a value.
public enum Literal {
    case scalar(ScalarLiteral)
    case tensor(TensorLiteral)
}

/// Scalar literal
public enum ScalarLiteral {
    case int(Int), float(Double), bool(Bool)

    public var typeBase: DataType.Base {
        switch self {
        case .bool: return .bool
        case .int: return .int
        case .float: return .float
        }
    }
}

/// Tensor literal
public enum TensorLiteral {
    case elements([ScalarLiteral])
    case random(from: ScalarLiteral, to: ScalarLiteral)
    case repeating(ScalarLiteral)

    public var typeBase: DataType.Base {
        switch self {
        case let .elements(elements):
            return elements[0].typeBase
        case let .random(from: lowerbound, to: _):
            return lowerbound.typeBase
        case let .repeating(value):
            return value.typeBase
        }
    }
}

/// Literal value. It wraps `Literal` into a value
public struct LiteralValue : Value {
    public var shape: TensorShape
    public var type: DataType
    public var literal: Literal
    public static let scope: Scope = .none

    public init(shape: TensorShape, type: DataType, literal: Literal) {
        self.shape = shape
        self.type = type
        self.literal = literal
    }
}

/// Anything that has a name
public protocol Named {
    var name: String { get }
}

/// Anything that may have a name
public protocol MaybeNamed {
    var name: String? { get }
}

public protocol Definition : class, Named, Value {
    var name: String { get }
    var shape: TensorShape { get }
}

/// When a value has a name, it's a unique Def!
public class Def<ValueType : Value> : Named, Definition, Value, HashableByReference {
    public typealias UserType = Instruction
    public var name: String
    public var shape: TensorShape
    public var type: DataType
    public var value: ValueType

    public static var scope: Scope {
        return ValueType.scope
    }
    
    public init(name: String, value: ValueType) {
        self.name = name
        self.shape = value.shape
        self.type = value.type
        self.value = value
    }
}

/// A value is potentially recurrent if it's potentially recurrent
public protocol PotentiallyRecurrentValue : Value {
    var isRecurrent: Bool { get }
}

// MARK: - Recurrent value helper
public extension Def where ValueType : PotentiallyRecurrentValue {
    public var isRecurrent: Bool {
        return value.isRecurrent
    }
}

// MARK: - Value helper factories
public extension Value {
    /// Returns a zero value of the same shape and the same data type
    func makeZero() -> LiteralValue {
        let literal: Literal
        switch (type.base, shape) {
        case (.bool, []):
            literal = .scalar(.bool(false))
        case (.float, []):
            literal = .scalar(.float(0))
        case (.int, []):
            literal = .scalar(.int(0))
        case (.bool, _):
            literal = .tensor(.repeating(.bool(false)))
        case (.float, _):
            literal = .tensor(.repeating(.float(0)))
        case (.int, _):
            literal = .tensor(.repeating(.int(0)))
        }
        return LiteralValue(shape: shape, type: type, literal: literal)
    }
}

/// User, anything that can use a value
public protocol User {
    var operands: [Use] { get }
}
