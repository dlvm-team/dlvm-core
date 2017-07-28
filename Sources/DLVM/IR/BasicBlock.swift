//
//  BasicBlock.swift
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

public class Argument : Value, Named, HashableByReference {
    public var name: String
    public var type: Type
    public unowned var parent: BasicBlock

    public init(name: String, type: Type, parent: BasicBlock) {
        self.name = name
        self.type = type
        self.parent = parent
    }

    public func makeUse() -> Use {
        return .argument(type, self)
    }
}

public final class BasicBlock : IRCollection, IRUnit, Named {
    public typealias Base = OrderedSet<Instruction>
    public typealias Element = Instruction

    /// Name of the basic block
    open var name: String
    open var arguments: OrderedSet<Argument> = []
    open var elements: OrderedSet<Instruction> = []
    open unowned var parent: Function
    public internal(set) var analysisManager: AnalysisManager<BasicBlock> = AnalysisManager()

    internal init<C: Collection>(name: String, arguments: C, parent: Function)
        where C.Iterator.Element == Argument
    {
        self.name = name
        self.arguments.append(contentsOf: arguments)
        self.parent = parent
        /// Set parent of each arg to self
        for arg in arguments {
            arg.parent = self
        }
    }

    public convenience init<C: Collection>(name: String, arguments: C, parent: Function)
        where C.Iterator.Element == (String, Type)
    {
        self.init(name: name, arguments: [] as [Argument], parent: parent)
        for (name, type) in arguments {
            let arg = Argument(name: name, type: type, parent: self)
            self.arguments.append(arg)
        }
    }

    public var canApplyTransforms: Bool {
        return true
    }

}

/// - Note: This is a workaround for a type checker bug in Swift 4
public extension BasicBlock {
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

// MARK: - Predicates and accessors
public extension BasicBlock {

    /// Whether there exists a terminator instruction
    /// - Note: a branching instruction in the middle of the basic block
    /// is not considered a terminator
    var hasTerminator: Bool {
        return elements.last?.kind.isTerminator ?? false
    }

    /// Terminator instruction
    var terminator: Instruction? {
        guard let last = elements.last, last.kind.isTerminator else {
            return nil
        }
        return last
    }

    var successorCount: Int {
        return terminator?.controlFlowSuccessorCount ?? 0
    }

    var hasSuccessors: Bool {
        return successorCount > 0
    }

    var isReturn: Bool {
        return terminator?.kind.isReturn ?? false
    }

    var module: Module {
        return parent.parent
    }

    var isEntry: Bool {
        return name == "entry"
    }

}

// MARK: - Arguments
public extension BasicBlock {
    func acceptsArguments<C : Collection>(_ types: C) -> Bool where C.Iterator.Element == Type {
        return types.elementsEqual(arguments.map{$0.type})
    }
}
