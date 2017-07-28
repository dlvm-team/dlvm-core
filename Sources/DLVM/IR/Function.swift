//
//  Intrinsics.swift
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

public final class Function : Named, IRCollection, IRUnit {
    public enum Attribute {
        /// Inline the function during LLGen
        case inline
    }

    public enum DeclarationKind {
        /// Externally defined
        case external
        /// Mark the function as the gradient of another with given configuration. To be
        /// materialized as a normally defined function by AD.
        /// - Parameters:
        ///   - from: index of tuple element to differentiate, when the return type is
        ///           a tuple; otherwise must be 0
        ///   - wrt: indices of arguments to differentiate the function with respect to
        ///   - keeping: indices of return values to kept in the gradient function, when
        ///              the return type is a tuple; otherwise can be [0] or []
        /// - Note: The type of the function must match that given by the configuration
        case gradient(of: Function, from: Int?, wrt: [Int], keeping: [Int], seedable: Bool)
    }

    public typealias Base = OrderedSet<BasicBlock>
    public typealias Element = BasicBlock

    public var name: String
    public var argumentTypes: [Type]
    public var returnType: Type
    public var attributes: Set<Attribute> = []
    public var declarationKind: DeclarationKind?
    public unowned var parent: Module

    public var elements: OrderedSet<BasicBlock> = []
    public internal(set) var analysisManager: AnalysisManager<Function> = AnalysisManager()

    public init(name: String, argumentTypes: [Type],
                returnType: Type, attributes: Set<Attribute> = [],
                declarationKind: DeclarationKind? = nil, parent: Module) {
        self.name = name
        self.argumentTypes = argumentTypes
        self.returnType = returnType
        self.attributes = attributes
        self.declarationKind = declarationKind
        self.parent = parent
    }

    public var canApplyTransforms: Bool {
        return !isDeclaration
    }
}

/// - Note: This is a workaround for a type checker bug in Swift 4
public extension Function {
    func remove(_ element: Element) {
        elements.remove(element)
        invalidateAnalyses()
    }

    func contains(_ element: Element) -> Bool {
        return elements.contains(element)
    }

    func append(_ newElement: Element) {
        elements.append(newElement)
        newElement.parent = self
        invalidateAnalyses()
    }

    func insert(_ newElement: Element, at index: Base.Index) {
        elements.insert(newElement, at: index)
        newElement.parent = self
        invalidateAnalyses()
    }

    func insert(_ newElement: Element, after other: Element) {
        elements.insert(newElement, after: other)
        newElement.parent = self
        invalidateAnalyses()
    }

    func insert(_ newElement: Element, before other: Element) {
        elements.insert(newElement, before: other)
        newElement.parent = self
        invalidateAnalyses()
    }
}

extension Function : Value {
    public var type: Type {
        return .function(argumentTypes, returnType)
    }

    public func makeUse() -> Use {
        return .function(type, self)
    }
}

public extension Function {
    func acceptsArguments<C : Collection>(_ types: C) -> Bool where C.Iterator.Element == Type, C.IndexDistance == Int {
        guard types.count == argumentTypes.count else { return false }
        return zip(types, argumentTypes).forAll { actual, formal in
            actual.conforms(to: formal)
        }
    }

    var isDeclaration: Bool {
        return declarationKind != nil
    }

    var isDefinition: Bool {
        return declarationKind == nil
    }

    var instructions: LazyCollection<FlattenBidirectionalCollection<Function>> {
        return lazy.joined()
    }
}

public extension Function {
    /// Remove all uses of this value in the function
    func replaceAllUses(of oldInstruction: Instruction, with newUse: Use) {
        /// If `instruction` exists in its parent BB in this function,
        /// we only search the area after `instruction`'s definition
        if oldInstruction.existsInParent, oldInstruction.parent.parent == self {
            let bbIndex = oldInstruction.parent.indexInParent
            let instIndex = oldInstruction.indexInParent
            for bb in suffix(from: bbIndex) {
                for inst in bb {
                    if bb == inst.parent, inst.indexInParent < instIndex {
                        continue
                    }
                    inst.substitute(newUse, for: %oldInstruction)
                }
            }
        }
        /// Otherwise, we search every use for `instruction`
        else {
            for inst in instructions {
                inst.substitute(newUse, for: %oldInstruction)
            }
        }
    }
}

public extension Function {
    func gradientType(fromOutput diffIndex: Int?,
                      withRespectTo varIndices: [Int],
                      keepingOutputs outputIndices: [Int],
                      isSeedable: Bool) -> Type? {
        var keptOutputs: [Type]
        let diffSourceType: Type
        /// Check output index
        switch returnType {
        /// Tuple output is treated as multiple-out
        case let .tuple(elementTypes):
            guard let diffIndex = diffIndex,
                /// Diff index must be in bounds
                elementTypes.indices.contains(diffIndex),
                /// Indices of the outputs to keep must be in bounds
                let someOutputs = elementTypes.subcollection(atIndices: outputIndices),
                /// Indices of the outputs to keep must not contain any duplicate
                !outputIndices.containsDuplicate
                else { return nil }
            diffSourceType = elementTypes[diffIndex]
            keptOutputs = someOutputs
        /// Other output is treated as single out
        case _ where diffIndex == nil
                /// Result must be differentiable
                && returnType.isDifferentiable
                /// Indices of the outputs to keep must be either [] or [0]
                && (outputIndices.isEmpty || outputIndices == [0]):
            diffSourceType = returnType
            keptOutputs = outputIndices.isEmpty ? [] : [returnType]
        /// Bad differentiation case
        default:
            return nil
        }
        guard
            /// Indices of diff variables must be in bounds
            let diffVars = argumentTypes.subcollection(atIndices: varIndices),
            /// All diff variables must be diff'able arguments
            diffVars.forAll({$0.isDifferentiable})
            else { return nil }
        /// Result of differentiation has the same input types but different output types
        /// Output type is `(k1, ..., kn, d1, ..., dn)` where `k1...kn` are outputs of the 
        /// original function to keep, `d1...dn` are derivatives of the output at `diffIndex`
        /// with respect to arguments at indices `varIndices`, respectively.
        return .function(isSeedable ? argumentTypes + [diffSourceType] : argumentTypes,
                         .tuple(keptOutputs + diffVars))
    }
}
