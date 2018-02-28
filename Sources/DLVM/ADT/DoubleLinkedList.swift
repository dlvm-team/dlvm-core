import Foundation


public class ListNode<T: Equatable> {
  public let value: T
  var next: ListNode<T>? = nil
  var previous: ListNode<T>? = nil
  public init(value: T) {
    self.value = value
  }
}
extension ListNode: CustomStringConvertible {
  public var description: String {
    get {
      return "Value of list node: (\(value))"
    }
  }
}

public final class DoubleLinkedList<T: Equatable> {  

  var start: ListNode<T>? {
    didSet {
      if end == nil {
        end = start
      }
    }
  }
  
  var end: ListNode<T>? {
    didSet {
      if start == nil {
        start = end
      }
    }
  }
  
  public var count: Int = 0
  
  public var isEmpty: Bool {
    get {
      return count == 0
    }
  }
  
  public init() {
    
  }

  public init<S: Sequence>(_ elements: S) where S.Iterator.Element == T {
    for element in elements {
      append(value: element)
    }
  }
}


// TODO: need to add append after and append before, if this is to replace OrderedSet
extension DoubleLinkedList {
  
  private func iterate(block: (_ node: ListNode<T>, _ index: Int) throws -> ListNode<T>?) rethrows -> ListNode<T>? {
    var node = start
    var index = 0
    
    while node != nil {
      let result = try block(node!, index)
      if result != nil {
        return result
      }
      index += 1
      node = node?.next
    }
    return nil
  }
  
  public func nodeAt(index: Int) -> ListNode<T> {
    precondition(index >= 0 && index < count, "This index: \(index) is out of bounds. Accepted range is between 0 and \(count)")
    
    let result = iterate {
      if $1 == index {
        return $0
      }
      return nil
    }
    return result!
  }

  public func valueAt(index: Int) -> T {
    let node = nodeAt(index: index)
    return node.value
  }
  
  public func append(value: T) {
    let lastEnd = end
    end = ListNode<T>(value: value)
    end?.previous = lastEnd
    lastEnd?.next = end
    count += 1
  }

  public func remove(node: ListNode<T>) {
    let nextNode = node.next
    let previousNode = node.previous
    
    if node === start && node === end {
      start = nil
      end = nil
    }else if node === start {
      start = node.next
    }else {
      previousNode?.next = nextNode
      nextNode?.previous = previousNode
    }
    count -= 1
    assert((end != nil && start != nil && count >= 1) || (end == nil && start == nil && count == 0),
           "Invalid remove operation")
  }

  public func remove(atIndex index: Int) {
    precondition(index >= 0 && index < count ,  "This index: \(index) is out of bounds. Accepted range is between 0 and \(count)")
    let result = iterate {
      if $1 == index {
        return $0
      }
      return nil
    }
    remove(node: result!)
  }
}

// COW tings
extension DoubleLinkedList {
  func copy() -> DoubleLinkedList<T> {
    let newList = DoubleLinkedList<T>()
    for element in self {
      newList.append(value: element.value)
    }
    return newList
  }
}

public struct DoubleLinkedListCOW<T: Equatable> {
  
  var storage: DoubleLinkedList<T>
  var mutableStorage: DoubleLinkedList<T> {
    mutating get {
      if !isKnownUniquelyReferenced(&storage) {
        storage = storage.copy()
      }
      return storage
    }
  }
  
  public init() {
    storage = DoubleLinkedList()
  }
  
  public init<S: Sequence> (_ elements: S) where S.Iterator.Element == T {
    storage = DoubleLinkedList(elements)
  }
  public var count: Int {
    get {
      return storage.count
    }
  }
  public var isEmpty: Bool {
    get {
      return storage.isEmpty
    }
  }
  public mutating func append(value: T) {
    mutableStorage.append(value: value)
  }
  public func nodeAt(index: Int) -> ListNode<T> {
    return storage.nodeAt(index: index)
  }
  public func valueAt(index: Int) -> T {
    let node = nodeAt(index: index)
    return node.value
  }
  public mutating func remove(node: ListNode<T>) {
    mutableStorage.remove(node: node)
  }
  public mutating func remove(atIndex index: Int) {
    mutableStorage.remove(atIndex: index)
  }
}

