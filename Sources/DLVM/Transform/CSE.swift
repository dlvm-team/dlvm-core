//
//  CSE.swift
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

/// Eliminates common subexpressions in a function
/// WIP: Currently only eliminates trivially redundant instructions
open class CommonSubexpressionElimination : TransformPass {
    public typealias Body = Function

    open class func run(on body: Function) -> Bool {
        var changed: Bool = false
        var availableValues: Set<Instruction> = []
        var count = 0
        /// Iterate over the original function
        for inst in body.instructions {
            changed = performCSE(on: inst, availableValues: &availableValues, count: &count) || changed
        }
        return changed
    }

    private static func performCSE(on inst: Instruction,
                                   availableValues: inout Set<Instruction>,
                                   count: inout Int) -> Bool {
        let function = inst.parent.parent
        let module = function.parent
        let domTree = function.analysis(from: DominanceAnalysis.self)
        let sideEffectInfo = module.analysis(from: SideEffectAnalysis.self)

        /// If instruction has side effects or is a terminator, change nothing
        guard sideEffectInfo[inst] == .none,
            !inst.kind.isTerminator else { return false }

        /// If instruction does not match a dominating available value, add it to
        /// available values
        guard let available = availableValues.first(where: { $0.kind == inst.kind }),
            domTree.properlyDominates(available, inst) else {
                availableValues.insert(inst)
                return false
        }
        /// Otherwise, replace instruction with corresponding available value
        inst.removeFromParent()
        function.replaceAllUses(of: inst, with: %available)
        count += 1
        return true
    }
}
