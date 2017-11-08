//
//  MatrixMultiplicationReordering.swift
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

import struct CoreTensor.TensorShape

open class MatrixMultiplicationReordering : TransformPass {
    public typealias Body = Function
    
    private typealias Chain = [(operand: Use, shape: TensorShape)]

    private indirect enum Expression {
        case matrix(operand: Use)
        case dot(Expression, Expression)
    }
    
    private static func optimizedExpression(for chain: Chain) -> (Int, Expression) {
        /// Lay out dimensions
        var dims: [Int] = []
        dims.append(chain[0].shape[0])
        dims.append(contentsOf: chain.map{$0.shape[1]})
        /// Compute cost matrix
        var temp: [[Int]] = Array(repeating: Array(repeating: 0, count: dims.count), count: dims.count)
        var cost = temp
        for l in 1 ..< dims.count - 1 {
            for i in 1 ..< dims.count - l {
                let j = i + l
                cost[i][j] = Int.max
                for k in i..<j {
                    let newCost = dims[i-1] * dims[k] * dims[j]
                    let q = cost[i][k] + cost[k+1][j] + newCost
                    if (q < cost[i][j]) {
                        cost[i][j] = q
                        temp[i][j] = k
                    }
                }
            }
        }
        /// Construct expression
        func makeExpression(_ i: Int, _ j: Int) -> Expression {
            return i == j
                ? .matrix(operand: chain[i-1].operand)
                : .dot(makeExpression(i, temp[i][j]), makeExpression(temp[i][j] + 1, j))
        }
        /// Return cost and expression
        let expr = makeExpression(1, dims.count - 1)
        return (cost[1][dims.count - 1], expr)
    }
    
    open class func run(on body: Function) -> Bool {
        let dfg = body.analysis(from: DataFlowGraphAnalysis.self)
        let builder = IRBuilder(function: body)
        var visited: Set<Instruction> = []
        var changed = false
        var chains: [(chain: Chain, instructions: [Instruction])] = []
        /// Collect chains of matrix multiplication
        for bb in body {
            for inst in bb.reversed() where !visited.contains(inst) {
                guard inst.opcode == .dot else { continue }
                var chain: [(operand: Use, shape: TensorShape)] = []
                var insts: [Instruction] = []
                /// Collect operands
                for next in inst.transposeTraversed(in: .postorder) {
                    visited.insert(next)
                    /// Must be dot
                    guard case let .dot(lhs, rhs) = next.kind else { continue }
                    /// Must have exactly one user
                    let users = dfg.successors(of: next)
                    guard users.count == 1 else { continue }
                    /// Get shapes
                    guard case let (.tensor(s1, _), .tensor(s2, _)) = (lhs.type.canonical, rhs.type.canonical) else {
                        preconditionFailure("Ill-formed instruction \(inst)")
                    }
                    /// Append to chain
                    chain.append((operand: lhs, shape: s1))
                    chain.append((operand: rhs, shape: s2))
                    insts.append(next)
                }
                chains.append((chain: chain, instructions: insts))
            }
        }
        /// Run algorithm for each chain
        for (chain, insts) in chains {
            let (_, expr) = optimizedExpression(for: chain)
            /// - TODO: Compare new expression with old expression. If they are equal,
            /// then no modification is needed.
            /// Insert new instructions after insts
            let topInst = insts.last!
            builder.move(after: topInst)
            func insert(_ expr: Expression) -> Use {
                switch expr {
                case let .matrix(operand: op):
                    return op
                case let .dot(lhs, rhs):
                    return %builder.dot(insert(lhs), insert(rhs))
                }
            }
            let newTopInst = insert(expr)
            body.replaceAllUses(of: topInst, with: newTopInst)
            for oldInst in insts {
                oldInst.removeFromParent()
            }
            changed = true
        }
        return changed
    }
}
