//
//  IRUnit.swift
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

public protocol EquatableByReference : class, Equatable {}
public protocol HashableByReference : EquatableByReference, Hashable {}

public extension EquatableByReference {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs === rhs
    }
}

public extension HashableByReference {
    public var hashValue: Int {
        return ObjectIdentifier(self).hashValue
    }
}

public protocol IRUnit : class, HashableByReference, Verifiable {
    associatedtype Parent : AnyObject // : IRCollection
    unowned var parent: Parent { get set }

    /// Swift 4 sema workaround
    var existsInParent: Bool { get }
    var indexInParent: Int { get }
    func removeFromParent()
}

/// Swift 4 sema workaround
public extension BasicBlock {
    var indexInParent: Int {
        guard let index = parent.index(of: self) else {
            preconditionFailure("Self does not exist in parent basic block")
        }
        return index
    }

    var existsInParent: Bool {
        return parent.contains(self)
    }

    func removeFromParent() {
        parent.remove(self)
    }
}

/// Swift 4 sema workaround
public extension Instruction {
    var indexInParent: Int {
        guard let index = parent.index(of: self) else {
            preconditionFailure("Self does not exist in parent basic block")
        }
        return index
    }

    var existsInParent: Bool {
        return parent.contains(self)
    }

    func removeFromParent() {
        parent.remove(self)
    }
}

/// Swift 4 sema workaround
public extension Function {
    var indexInParent: Int {
        guard let index = parent.index(of: self) else {
            preconditionFailure("Self does not exist in parent basic block")
        }
        return index
    }

    var existsInParent: Bool {
        return parent.contains(self)
    }

    func removeFromParent() {
        parent.remove(self)
    }
}

/*
public extension IRUnit where Parent.Element == Self {
    var indexInParent: Int {
        guard let index = parent.index(of: self) else {
            preconditionFailure("Self does not exist in parent basic block")
        }
        return index
    }

    var existsInParent: Bool {
        return parent.contains(self)
    }

    func removeFromParent() {
        parent.remove(self)
    }
}
*/
