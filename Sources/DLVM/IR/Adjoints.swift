//
//  Adjoints.swift
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

import struct CoreTensor.TensorShape

extension InstructionKind {
    public func operandAdjoints(
        using bd: IRBuilder, primal: Use, seed: Use, operands: [Use]
    ) -> [(operand: Use, adjoint: Use)]? {
        /// Primal/adjoint pairs for operands
        var adjoints: [(operand: Use, adjoint: Use)] = []
        /// Operand differentiation utility
        func differentiateOperand(at index: Int, with fn: (Use) -> Use) {
            let operand = operands[index]
            if case .literal = operand { return }
            adjoints.append((operand: operand, adjoint: fn(operand)))
        }
        /// Unbroadcasting utility
        func unbroadcastIfNeeded(_ x: Use, to y: Use) -> Use {
            guard case let .tensor(s1, _) = x.type else {
                fatalError("\(x) is not a tensor")
            }
            guard case let .tensor(s2, _) = y.type else {
                fatalError("\(y) is not a tensor")
            }
            let reductionAxes = s1.indices
                .filter { (index: Int) in index >= s2.count || s1[s1.count - index - 1] < s2[s2.count - index - 1] }
                .map { (index: Int) in s1.count - index - 1 }
            /// If no need to sum, return original x
            if reductionAxes.isEmpty { return x }
            let sum = bd.reduce(.numeric(.add), x,
                                initial: %x.makeScalar(0), dims: reductionAxes)
            guard case let .tensor(s3, _) = sum.type else { DLImpossible() }
            /// If no need to shape cast, return sum
            if s2 == s3 { return %sum }
            /// Return shape-casted sum
            return %bd.shapeCast(%sum, to: s2)
        }

        switch self {
        /** Literal constructor **/
        case .literal:
            for operand in operands {
                /// Skip literal operands
                if case .literal = operand { continue }
                /// ∂f/∂x = 0
                adjoints.append((operand, operand.makeLiteral(0, using: bd).makeUse()))
            }

        /** Unary elementwise operations **/
        case .numericUnary(.log, _):
            /// ∂f/∂x = D / x
            differentiateOperand(at: 0, with: { x in %bd.divide(seed, x) })
        case .numericUnary(.cos, _):
            /// ∂f/∂x = -D * sin(x)
            differentiateOperand(at: 0, with: { x in
                %bd.multiply(%bd.numeric(.negate, seed), %bd.numeric(.sin, x))
            })
        case .numericUnary(.sin, _):
            /// ∂f/∂x = D * cos(x)
            differentiateOperand(at: 0, with: { x in
                %bd.multiply(seed, %bd.numeric(.cos, x))
            })
        case .numericUnary(.tan, _):
            /// ∂f/∂x = D / (cos(x) * cos(x))
            differentiateOperand(at: 0, with: { x in
                let cosx = %bd.numeric(.cos, x)
                return %bd.divide(seed, %bd.multiply(cosx, cosx))
            })
        case .numericUnary(.cosh, _):
            /// ∂f/∂x = D * sinh(x)
            differentiateOperand(at: 0, with: { x in
                %bd.multiply(seed, %bd.numeric(.sinh, x))
            })
        case .numericUnary(.sinh, _):
            /// ∂f/∂x = D * cosh(x)
            differentiateOperand(at: 0, with: { x in
                %bd.multiply(seed, %bd.numeric(.cosh, x))
            })
        case .numericUnary(.tanh, _):
            /// ∂f/∂x = D * (1 - (f * f))
            differentiateOperand(at: 0, with: { x in
                %bd.multiply(
                    seed,
                    %bd.subtract(%x.makeScalar(1), %bd.multiply(primal, primal))
                )
            })
        case .numericUnary(.acos, _):
            /// ∂f/∂x = -D / sqrt(1 - (x * x))
            differentiateOperand(at: 0, with: { x in
                %bd.divide(
                    %bd.numeric(.negate, seed),
                    %bd.numeric(.sqrt, %bd.subtract(%x.makeScalar(1), %bd.multiply(x, x)))
                )
            })
        case .numericUnary(.asin, _):
            /// ∂f/∂x = D / sqrt(1 - (x * x))
            differentiateOperand(at: 0, with: { x in
                %bd.divide(
                    seed,
                    %bd.numeric(.sqrt, %bd.subtract(%x.makeScalar(1), %bd.multiply(x, x)))
                )
            })
        case .numericUnary(.atan, _):
            /// ∂f/∂x = D / (1 + (x * x))
            differentiateOperand(at: 0, with: { x in
                %bd.divide(seed, %bd.add(%x.makeScalar(1), %bd.multiply(x, x)))
            })
        case .numericUnary(.exp, _):
            /// ∂f/∂x = f * D
            differentiateOperand(at: 0, with: { _ in
                %bd.multiply(primal, seed)
            })
        case .numericUnary(.sqrt, _):
            /// ∂f/∂x = D / (2 * f)
            differentiateOperand(at: 0, with: { x in
                %bd.divide(seed, %bd.multiply(%x.makeScalar(2), primal))
            })
        case .numericUnary:
            /// Adjoints for remaining cases not yet implemented
            DLUnimplemented()

        /** Binary elementwise operations **/
        case .numericBinary(.add, _, _):
            /// ∂f/∂x = D
            differentiateOperand(at: 0, with: { lhs in
                unbroadcastIfNeeded(seed, to: lhs)
            })
            /// ∂f/∂y = D
            differentiateOperand(at: 1, with: { rhs in
                unbroadcastIfNeeded(seed, to: rhs)
            })
        case .numericBinary(.subtract, _, _):
            /// ∂f/∂x = D
            differentiateOperand(at: 0, with: { lhs in
                unbroadcastIfNeeded(seed, to: lhs)
            })
            /// ∂f/∂y = -D
            differentiateOperand(at: 1, with: { rhs in
                unbroadcastIfNeeded(%bd.numeric(.negate, seed), to: rhs)
            })
        case .numericBinary(.multiply, _, _):
            let lhs = operands[0]
            let rhs = operands[1]
            /// ∂f/∂x = D * y
            differentiateOperand(at: 0, with: { lhs in
                unbroadcastIfNeeded(%bd.multiply(seed, rhs), to: lhs)
            })
            /// ∂f/∂y = D * x
            differentiateOperand(at: 1, with: { rhs in
                unbroadcastIfNeeded(%bd.multiply(seed, lhs), to: rhs)
            })
        case .numericBinary(.divide, _, _):
            let lhs = operands[0]
            let rhs = operands[1]
            /// ∂f/∂x = D / y
            differentiateOperand(at: 0, with: { lhs in
                %bd.divide(seed, rhs)
            })
            /// ∂f/∂y = -x / y^2
            differentiateOperand(at: 1, with: { rhs in
                %bd.numeric(.negate, %bd.divide(lhs, %bd.multiply(rhs, rhs)))
            })
        case .numericBinary(.power, _, _):
            let lhs = operands[0]
            let rhs = operands[1]
            /// ∂f/∂x = y * x^(y - 1) * D
            differentiateOperand(at: 0, with: { lhs in
                %bd.multiply(
                    %bd.multiply(rhs, %bd.power(lhs, %bd.subtract(rhs, %rhs.makeScalar(1)))),
                    seed
                )
            })
            /// ∂f/∂y = ln(x) * f * D
            differentiateOperand(at: 1, with: { rhs in
                %bd.numeric(.negate, %bd.divide(lhs, %bd.multiply(rhs, rhs)))
            })
        case .numericBinary(.min, _, _),
             .numericBinary(.max, _, _):
            /// Adjoint for min/max not yet implemented
            /// Implementation should include a special equality tiebreaker
            DLUnimplemented()

        case .dataTypeCast:
            differentiateOperand(at: 0, with: { x in
                guard case let .tensor(_, xdt) = x.type else {
                    fatalError("\(x) is not a tensor")
                }
                return %bd.dataTypeCast(seed, to: xdt)
            })
        case .dot:
            let lhs = operands[0]
            let rhs = operands[1]
            /// ∂f/∂x = D • y^T
            differentiateOperand(at: 0, with: { lhs in
                %bd.dot(seed, %bd.transpose(rhs))
            })
            /// ∂f/∂y = x^T • D
            differentiateOperand(at: 1, with: { rhs in
                %bd.dot(%bd.transpose(lhs), seed)
            })
        case .transpose:
            /// ∂f/∂x = D^T
            differentiateOperand(at: 0, with: { x in
                %bd.transpose(seed)
            })
        case let .reverse(_, dims):
            /// ∂f/∂x = reverse(D, dims)
            differentiateOperand(at: 0, with: { x in
                %bd.reverse(seed, dims: dims)
            })
        case let .slice(_, at: range):
            /// ∂f/∂x = slice(D, at: range)
            differentiateOperand(at: 0, with: { x in
                %bd.slice(seed, at: range)
            })

        case .compare:
            DLUnimplemented()
        case .select:
            DLUnimplemented()
        case .scan:
            DLUnimplemented()
        case .reduce:
            DLUnimplemented()
        case .concatenate:
            DLUnimplemented()
        case .reduceWindow:
            DLUnimplemented()
        case .convolve:
            DLUnimplemented()
        case .rank:
            DLUnimplemented()
        case .shape:
            DLUnimplemented()
        case .unitCount:
            DLUnimplemented()

        /** Cost-free casts **/
        case let .padShape(_, at: i):
            differentiateOperand(at: 0, with: { x in
                /// When dimension is known to be 1, calculate adjoint using
                /// squeezeShape
                if i == 1 {
                    /// ∂f/∂x = squeezeShape(D, at: i)
                    return %bd.squeezeShape(seed, at: i)
                }
                /// Otherwise, sum over the dimension
                else {
                    /// ∂f/∂x = sum(D, along: i)
                    return %bd.reduce(.numeric(.add), seed,
                                      initial: %x.makeScalar(0), dims: [i])
                }
            })
        case let .squeezeShape(_, at: i):
            /// ∂f/∂x = padShape(D, at: i)
            differentiateOperand(at: 0, with: { x in
                %bd.padShape(seed, at: i)
            })
        case let .shapeCast(_, to: s):
            /// ∂f/∂x = shapecast(D, to: s)
            differentiateOperand(at: 0, with: { x in
                %bd.shapeCast(seed, to: s)
            })
        case let .bitCast(_, to: t):
            /// ∂f/∂x = bitcast(D, at: t)
            differentiateOperand(at: 0, with: { x in
                %bd.bitCast(seed, to: t)
            })

        /** Aggregate operations **/
        case let .extract(from: _, at: i):
            /// ∂f/∂x = extract(from: D, at: i)
            differentiateOperand(at: 0, with: { x in
                %bd.extract(from: seed, at: i)
            })

        /** Function application **/
        case .apply:
            /// Adjoint of function application is a special case that
            /// should be handled by the user.
            return nil

        /// The following instructions are not differentiable because they:
        /// - are related to control-flow
        /// - are boolean operations
        /// - are integer math operations
        /// - are random operations
        /// - are related to the stack data structure
        /// - access memory
        case .branch, .branchEnum, .conditional, .return,
             .not, .booleanBinary,
             .numericBinary(.modulo, _, _),
             .numericBinary(.floorDivide, _, _),
             .numericBinary(.truncateDivide, _, _),
             .random,
             .createStack, .destroyStack, .push, .pop,
             .insert, .allocateStack, .allocateHeap, .allocateBox, .projectBox,
             .retain, .release, .deallocate, .load, .store, .elementPointer, .copy,
             .trap, .builtin(_, _):
            return nil
        }
        return adjoints
    }
}
