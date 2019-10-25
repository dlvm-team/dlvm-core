//
//  BasicBlock.swift
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

public class Argument : NamedValue, HashableByReference {
    public var name: String?
    public var type: Type
    public unowned var parent: BasicBlock

    public init(name: String?, type: Type, parent: BasicBlock) {
        self.name = name
        self.type = type
        self.parent = parent
    }

    public func makeUse() -> Use {
        return .definition(.argument(self))
    }
}

public final class BasicBlock : IRCollection, IRUnit {
    public typealias Base = OrderedSet<Instruction>
    public typealias Element = Instruction

    /// Name of the basic block
    public var name: String?
    public var arguments: OrderedSet<Argument> = []
    public var elements: OrderedSet<Instruction> = []
    public var parent: Function
    public internal(set) var passManager: PassManager<BasicBlock> = PassManager()

    internal init<C: Collection>(name: String?, arguments: C, parent: Function)
        where C.Element == Argument
    {
        self.name = name
        self.arguments.append(contentsOf: arguments)
        self.parent = parent
        /// Set parent of each arg to self
        for arg in arguments {
            arg.parent = self
        }
    }

    public convenience init<C: Collection>(name: String?, arguments: C, parent: Function)
        where C.Element == (String?, Type)
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
    func append(_ newElement: Element) {
        elements.append(newElement)
        newElement.parent = self
        invalidatePassResults()
    }

    func insert(_ newElement: Element, at index: Base.Index) {
        elements.insert(newElement, at: index)
        newElement.parent = self
        invalidatePassResults()
    }

    func insert(_ newElement: Element, after other: Element) {
        elements.insert(newElement, after: other)
        newElement.parent = self
        invalidatePassResults()
    }

    func insert(_ newElement: Element, before other: Element) {
        elements.insert(newElement, before: other)
        newElement.parent = self
        invalidatePassResults()
    }
}

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
        return indexInParent == 0
    }
}

public extension BasicBlock {
    func acceptsArguments<C : Collection>(_ types: C) -> Bool
        where C.Element == Type
    {
        return types.elementsEqual(arguments.map{$0.type})
    }
}

// MARK: - Naming

public extension Argument {
    var printedName: String {
        if let name = name {
            return name
        }
        let selfIndex = parent.arguments.index(of: self) ?? DLImpossibleResult()
        return "\(parent.indexInParent)^\(selfIndex)"
    }
}

public extension BasicBlock {
    var printedName: String {
        return name ?? indexInParent.description
    }
}
