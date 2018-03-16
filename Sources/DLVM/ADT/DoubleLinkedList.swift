fileprivate class ListNode<T: Equatable> {
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
      return "Node(\(value))"
    }
  }
}

fileprivate final class DoubleLinkedList<T: Equatable> {  

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
  
  public init() {
    
  }

  public init<S: Sequence>(_ elements: S) where S.Iterator.Element == T {
    for element in elements {
      append(element)
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

  public var isEmpty: Bool {
    return count == 0
  }
  
  public func node(at index: Int) -> ListNode<T> {
    precondition(index >= 0 && index < count, "This index: \(index) is out of bounds. Accepted range is between 0 and \(count)")
    
    let result = iterate {
      if $1 == index {
        return $0
      }
      return nil
    }
    return result!
  }

  public func value(at index: Int) -> T {
    return node(at: index).value
  }

  public subscript(_ index: Int) -> T {
    return node(at: index).value
  }
  
  public func append(_ value: T) {
    let lastEnd = end
    end = ListNode<T>(value: value)
    end?.previous = lastEnd
    lastEnd?.next = end
    count += 1
  }

  func index(of element: T) -> Int? {
    var node = start
    var index = 0
    while node != nil {
      if node?.value == element {
        return index
      }
      index += 1
      node = node?.next
    }
    return nil
  }

  public func remove(_ node: ListNode<T>) {
    let nextNode = node.next
    let previousNode = node.previous
    
    if node === start && node === end {
      start = nil
      end = nil
    } else if node === start {
      start = node.next
    } else {
      previousNode?.next = nextNode
      nextNode?.previous = previousNode
    }
    count -= 1
    assert((end != nil && start != nil && count >= 1) || (end == nil && start == nil && count == 0),
           "Invalid remove operation")
  }

  public func remove(at index: Int) {
    precondition(index >= 0 && index < count ,  "This index: \(index) is out of bounds. Accepted range is between 0 and \(count)")
    let result = iterate {
      if $1 == index {
        return $0
      }
      return nil
    }
    remove(result!)
  }

  public func insert(_ element: T, at index: Int) {
    precondition(index >= 0 && index < count ,  "This index: \(index) is out of bounds. Accepted range is between 0 and \(count)")
    // find the desired node
    let result = iterate {
      if $1 == index {
        return $0
      }
      return nil
    }
    let newNode = ListNode<T>(value: element)
    let previousNode = result?.previous
    previousNode?.next = newNode
    result?.previous = newNode
    newNode.next = result
    newNode.previous = previousNode
  }

  func insert(_ element: T, before other: T) {
    guard let index = index(of: other) else {
            preconditionFailure("Element to insert before is not in the set")
    }
    insert(element, at: index)
  }

  func insert(_ element: T, after other: T) {
    guard let previousIndex = index(of: other) else {
        preconditionFailure("Element to insert after is not in the set")
    }
    insert(element, at: previousIndex + 1)
  }

}

// Make DoubleLinkedList conform to Sequence protocol
extension DoubleLinkedList: Sequence {

  public typealias Iterator = DoubleLinkedListGenerator<T>

  ///Return a *generator* over the elements of this *sequence*.
  public func makeIterator() -> Iterator {
    return DoubleLinkedListGenerator(linkedList: self)
  }
}


// create a Generator that conforms to IteratorProtocol
// TODO: this is skipping first element??
fileprivate struct DoubleLinkedListGenerator<T: Equatable>: IteratorProtocol {

  fileprivate let linkedList: DoubleLinkedList<T>
  fileprivate var current: ListNode<T>?

  fileprivate init(linkedList: DoubleLinkedList<T>) {
    self.linkedList = linkedList
    self.current = linkedList.start
  }

  ///Advance to the next element and return it, or `nil` if no next element exists.
  public mutating func next() -> ListNode<T>? {
    let node = self.current?.next
    self.current = node
    return node
  }
}


// COW extension
extension DoubleLinkedList {
  func copy() -> DoubleLinkedList<T> {
    let newList = DoubleLinkedList<T>()
    for element in self {
      newList.append(element.value)
    }
    return newList
  }
}

public struct IRList<T: Equatable> {
  
  fileprivate var storage: DoubleLinkedList<T>
  fileprivate var mutableStorage: DoubleLinkedList<T> {
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
}

extension IRList {
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
  public mutating func append(_ value: T) {
    mutableStorage.append(value)
  }
  private func node(at index: Int) -> ListNode<T> {
    return storage.node(at: index)
  }
  public func value(at index: Int) -> T {
    return node(at: index).value
  }
  fileprivate mutating func removeNode(_ node: ListNode<T>) {
    mutableStorage.remove(node)
  }
  public mutating func remove(at index: Int) {
    mutableStorage.remove(at: index)
  }
}

private var list = DoubleLinkedList<String>()
list.append("this")
list.append("is")
list.append("List")
list.append("more")
list.append("stuff")
list.append("after stuff")
list.append("aaa")
list.append("aaa")
list.append("aaa")
list.insert("should be inserted after stuff", after: "stuff")

for node in list {
  print("\(node)")
}

