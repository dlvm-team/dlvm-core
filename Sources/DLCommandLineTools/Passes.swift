//
//  Passes.swift
//  DLCommandLineTools
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

import DLVM

public func runPass(named name: String, on module: Module,
                    bypassingVerification noVerify: Bool = false) throws {
    var changed: Bool
    switch name {
    case "AD", "Differentiation":
        changed = module.applyTransform(Differentiation.self, bypassingVerification: noVerify)
    case "CP", "Checkpointing":
        changed = module.mapTransform(Checkpointing.self, bypassingVerification: noVerify)
    case "DCE", "DeadCodeElimination":
        changed = module.mapTransform(DeadCodeElimination.self, bypassingVerification: noVerify)
    case "CSE", "CommonSubexpressionElimination":
        changed = module.mapTransform(CommonSubexpressionElimination.self, bypassingVerification: noVerify)
    case "AS", "AlgebraSimplification":
        changed = module.mapTransform(AlgebraSimplification.self, bypassingVerification: noVerify)
    case "LAF", "LinearAlgebraFusion":
        changed = module.mapTransform(LinearAlgebraFusion.self, bypassingVerification: noVerify)
    case "SP", "StackPromotion":
        changed = module.mapTransform(StackPromotion.self, bypassingVerification: noVerify)
    case "VP", "ValuePromotion":
        changed = module.mapTransform(ValuePromotion.self, bypassingVerification: noVerify)
    case "MMR", "MatrixChainOrdering":
        changed = module.mapTransform(MatrixMultiplicationReordering.self, bypassingVerification: noVerify)
    case "LBP", "LiteralBroadcastingPromotion":
        changed = module.mapTransform(LiteralBroadcastingPromotion.self, bypassingVerification: noVerify)
    default:
        error("No transform pass named \(name)")
    }
    print("\(name):", changed ? "changed" : "unchanged")
}
