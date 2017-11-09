//
//  Op.swift
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

public typealias TensorType = (shape: TensorShape, dt: DataType)

public protocol TensorOp {
    associatedtype Configuration
    static func resultType(for config: Configuration) -> TensorType?
}

// MARK: - Operator definition

/// Unary op definition
public enum NumericUnaryOp {
    case sinh, cosh, tanh, log, exp, negate, sign, square, sqrt
    case round, rsqrt, ceil, floor
    case tan, cos, sin, acos, asin, atan
    case lgamma, digamma, erf, erfc, rint
}

/// Unary op type inference
extension NumericUnaryOp : TensorOp {
    public typealias Configuration = (TensorType)
    public static func resultType(for config: Configuration) -> TensorType? {
        let (ty) = config
        return ty
    }
}

/// Comparison op definition
public enum ComparisonOp {
    case lessThan, lessThanOrEqual
    case greaterThan, greaterThanOrEqual
    case equal, notEqual
}

/// Comparison op type inference
extension ComparisonOp : TensorOp {
    public typealias Configuration = (TensorType, TensorType)
    public static func resultType(for config: Configuration) -> TensorType? {
        let ((shape: s1, dt: dt1), (shape: s2, dt: dt2)) = config
        guard let bcShape = s1.broadcast(with: s2), dt1 == dt2, dt1.isNumeric else {
            return nil
        }
        return (bcShape, .bool)
    }
}

/// Boolean op definition
public enum BooleanOp {
    case and, or
}

extension BooleanOp : TensorOp {
    public typealias Configuration = (TensorType, TensorType)
    public static func resultType(for config: Configuration) -> TensorType? {
        let ((shape: s1, dt: dt1), (shape: s2, dt: dt2)) = config
        guard let bcShape = s1.broadcast(with: s2), dt1 == dt2, dt1.isBool else {
            return nil
        }
        return (bcShape, dt1)
    }
}

/// Numeric associative op definition
public enum NumericBinaryOp {
    case add, subtract, multiply, divide, min, max
    case truncateDivide, floorDivide, modulo, power, mean
}

/// Numeric associative op type inference
extension NumericBinaryOp : TensorOp {
    public typealias Configuration = (TensorType, TensorType)
    public static func resultType(for config: Configuration) -> TensorType? {
        let ((shape: s1, dt: dt1), (shape: s2, dt: dt2)) = config
        guard let bcShape = s1.broadcast(with: s2), dt1 == dt2, dt1.isNumeric else {
            return nil
        }
        return (bcShape, dt1)
    }
}

/// Boolean associative op definition
public enum BooleanBinaryOp {
    case and, or
}

/// Boolean associative op type inference
extension BooleanBinaryOp : TensorOp {
    public typealias Configuration = (TensorType, TensorType)
    public static func resultType(for config: Configuration) -> TensorType? {
        let ((shape: s1, dt: dt1), (shape: s2, dt: dt2)) = config
        guard let bcShape = s1.broadcast(with: s2), dt1 == dt2, dt1.isBool else {
            return nil
        }
        return (bcShape, dt1)
    }
}

/// Not
public enum NegationOp : TensorOp {
    public typealias Configuration = (TensorType)
    public static func resultType(for config: Configuration) -> TensorType? {
        guard case let ((s, .bool)) = config else { return nil }
        return (s, .bool)
    }
}

/// Concatenation
public enum ConcatenationOp : TensorOp {
    public typealias Configuration = ([TensorType], axis: Int)
    public static func resultType(for config: ([TensorType], axis: Int)) -> TensorType? {
        let (tt, axis) = config
        return tt.reduce(tt.first) { acc, next in
            let (nextShape, nextDataType) = next
            return acc.flatMap { accShape, accDataType in
                guard axis < accShape.rank, accDataType == nextDataType
                    else { return nil }
                return accShape.concatenating(with: nextShape, alongDimension: axis).flatMap { newShape in
                    (newShape, accDataType)
                }
            }
        }
    }
}

/// Transpose
public enum TransposeOp : TensorOp {
    public typealias Configuration = (TensorType)
    public static func resultType(for config: Configuration) -> TensorType? {
        let ((s, dt)) = config
        return (s.transpose, dt)
    }
}

/// Shape cast
public enum ShapeCastOp : TensorOp {
    public typealias Configuration = (TensorType, TensorShape)
    public static func resultType(for config: Configuration) -> TensorType? {
        let ((shape: s, dt: dt), newShape) = config
        guard s.contiguousSize == newShape.contiguousSize else { return nil }
        return (newShape, dt)
    }
}

/// Slice
public enum SliceOp : TensorOp {
    public typealias Configuration = (TensorType, at: CountableClosedRange<Int>)
    public static func resultType(for config: Configuration) -> TensorType? {
        var ((shape: s, dt: dt), range) = config
        guard let firstDim = s.first, range.contains(firstDim)
            else { return nil }
        s[0] = range.count
        return (s, dt)
    }
}

/// Random
public enum RandomOp : TensorOp {
    public typealias Configuration = (TensorShape, from: TensorType, upTo: TensorType)
    public static func resultType(for config: Configuration) -> TensorType? {
        guard case let (shape, (shape: .scalar, dt: dt1), (shape: .scalar, dt: dt2)) = config,
            dt1 == dt2, dt1.isNumeric
            else { return nil }
        return (shape, dt1)
    }
}

/// Select
public enum SelectOp : TensorOp {
    public typealias Configuration = (TensorType, TensorType, by: TensorType)
    public static func resultType(for config: Configuration) -> TensorType? {
        guard case let ((shape: s1, dt: dt1), (shape: s2, dt: dt2), (shape: s3, dt: .bool)) = config,
            dt1 == dt2, let shape = broadcast(s1, s2, s3)
            else { return nil }
        return (shape, dt1)
    }
}
