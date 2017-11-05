//
//  IRCollection.swift
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

/// IRCollection
public protocol IRCollection : class, RandomAccessCollection, Verifiable, PassResultCache
    where Index == Int
{
    associatedtype Base : OrderedSetCollection where Base.Element == Element
    var elements: Base { get set }
    var canApplyTransforms: Bool { get }
    /// - Note: This is a workaround for a type checker bug in Swift 4
    func remove(_ element: Element)
    func contains(_ element: Element) -> Bool
    func insert(_ newElement: Element, after other: Element)
    func insert(_ newElement: Element, before other: Element)
}

public extension IRCollection {

    func makeIterator() -> Base.Iterator {
        return elements.makeIterator()
    }

    func index(after i: Base.Index) -> Base.Index {
        return elements.index(after: i)
    }

    func index(before i: Base.Index) -> Base.Index {
        return elements.index(before: i)
    }

    var indices: Base.Indices {
        return elements.indices
    }

    var startIndex: Base.Index {
        return elements.startIndex
    }

    var endIndex: Base.Index {
        return elements.endIndex
    }

    subscript(i: Base.Index) -> Base.Element {
        return elements[i]
    }

    subscript(bounds: Range<Base.Index>) -> Base.SubSequence {
        return elements[bounds]
    }
}

/// - Note: This is a workaround for a type checker bug in Swift 4
/*
public extension IRCollection where Element : IRUnit {

    func remove(_ element: Element) {
        elements.remove(element)
        invalidatePassResults()
    }

    func contains(_ element: Element) -> Bool {
        return elements.contains(element)
    }
}

public extension IRCollection where Element : IRUnit, Element.Parent == Self {

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
*/
