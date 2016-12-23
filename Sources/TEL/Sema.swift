//
//  Sema.swift
//  DLVM
//
//  Created by Richard Wei on 12/18/16.
//
//  This file contains type checker and semantic analyzer
//

import enum DLVM.DataType
import struct DLVM.TensorShape

public enum SemanticError : Error {
    case typeMismatch
    case dataTypeRedeclared
    case inputRedeclared(Variable)
    case outputRedeclared(Variable)
    case initializerMissing(Variable)
    case initializerUnexpected(Variable)
    case inputMissing
    case outputMissing
}

public protocol Node {
    var name: String { get }
    var shape: TensorShape { get }
}

/// Parameter (param[xxx])
public class Parameter : Node {
    public enum Initializer {
        case int(Int)
        case float(Float)
        case intRandom(Int, Int)
        case floatRandom(Float, Float)
    }
    public let name: String
    public let shape: TensorShape
    public let initializer: Initializer

    public init(name: String, shape: TensorShape, initializer: Initializer) {
        self.name = name
        self.shape = shape
        self.initializer = initializer
    }
}

/// Input (in[])
public class Input : Node {
    public let name: String
    public let shape: TensorShape

    public init(name: String, shape: TensorShape) {
        self.name = name
        self.shape = shape
    }
}

/// Layer (hidden[])
public class Layer : Node {
    public let name: String
    public let shape: TensorShape

    /// Add dependency field

    public init(name: String, shape: TensorShape) {
        self.name = name
        self.shape = shape
    }
}

/// Output (out[])
public class Output : Layer { }

/// Environment for semantics analysis
/// To be passed to CodeGen
struct TypeEnvironment {
    private var shapes: [String : TensorShape] = [:]

    subscript(key: String) -> TensorShape? {
        get {
            return shapes[key]
        }
        set {
            shapes[key] = newValue
        }
    }
}

/// Program semantics
public class Program {

    /// Default type: float32
    public internal(set) var dataType: DataType = .float32

    public internal(set) var input: Input
    public internal(set) var output: Output
    public internal(set) var layers: [Layer] = []
    public internal(set) var parameters: [Parameter] = []
    
    var env = TypeEnvironment()

    init(_ parse: ProgramTree) throws {
        var dataTypeDefined = false

        var maybeInput: Input? = nil
        var maybeOutput: Output? = nil
        
        for stmt in parse.statements {
            
            switch stmt {
            /// Macro
            case let .macro(macro):
                /// Type declaraction
                if case let .type(type) = macro {
                    if dataTypeDefined {
                        throw SemanticError.dataTypeRedeclared
                    }
                    dataTypeDefined = true
                    self.dataType = type
                }
            /// Declaration
            case let .declaration(decl):
                switch decl {
                /// Input
                case let .assignment(variable, declType, nil)
                    where declType.role == .input:
                    guard maybeInput == nil else {
                        throw SemanticError.inputRedeclared(variable)
                    }
                    maybeInput = Input(
                        name: variable.name,
                        shape: TensorShape(declType.shape)
                    )

                /// No init expr for a non-input node, error
                case let .assignment(variable, _, nil):
                    throw SemanticError.initializerMissing(variable)

                /// Output
                case let .assignment(variable, declType, expr?)
                    where declType.role == .output:
                    guard maybeOutput == nil else {
                        throw SemanticError.outputRedeclared(variable)
                    }

                    switch expr {
                    case .int(_):
                        /// IDK what to do with these
                        break
                    case .float(_):
                        /// IDK what to do with these
                        break
                    case let .variable(sourceVar):
                        switch sourceVar {
                        case let .simple(sourceName):
                            switch variable {
                            case let .simple(targetName):
                                let source: TensorShape? = env[sourceName]
                                if declType.shape.count == source?.rank {
                                    env[targetName] = source
                                } else {
                                    throw SemanticError.typeMismatch
                                }
                            default:
                                /// trying to assign a simple variable to a recurrent variable
                                break
                            }
                        case let .recurrent(sourceName, timestep: sourceTimestep, offset: sourceOffset):
                            let source: TensorShape? = env[sourceName]
                            switch variable {
                            case let .recurrent(targetName, timestep: targetTimestep, offset: targetOffset):
                                //// not sure if this is right
                                if sourceTimestep == targetTimestep,
                                    sourceOffset  == targetOffset {
                                    env[targetName] = source
                                } else {
                                    throw SemanticError.typeMismatch
                                }
                            default:
                                /// trying to assign a recurrent variable to a simple variable
                                break
                            }
                        }
                        
                    case let .add(left, right):
                        switch (left, right) {
                        case let (.variable(l), .variable(r)):
                            //// result <- l + r
                            //// match type of result with declType
                            break
                        default:
                            throw SemanticError.typeMismatch
                        }
                        
                    case let .mul(left, right):
                        switch (left, right) {
                        case let (.variable(l), .variable(r)):
                            //// result <- l * r
                            //// match type of result with declType
                            break
                        default:
                            throw SemanticError.typeMismatch
                        }
                        
                    case let .product(left, right):
                        switch (left, right) {
                        case let (.variable(l), .variable(r)):
                            //// result <- l x r
                            //// match type of result with declType
                            break
                        default:
                            throw SemanticError.typeMismatch
                        }
                        
                    case let .concat(exprs):
                        break
                    default:
                        throw SemanticError.typeMismatch
                    }


                    ///try typeCheck(declaration: decl)

                    maybeOutput = Output(
                        name: variable.name,
                        shape: TensorShape(declType.shape)
                    )

                case let .recurrence(timestep, decls):
                    /// TODO: type-check recurrence block
                    break
                default:
                    break
                }
            }
        }
        guard let input = maybeInput else { throw SemanticError.inputMissing }
        self.input = input
        guard let output = maybeOutput else { throw SemanticError.outputMissing }
        self.output = output
    }
//
//
//    func typeCheck(declaration decl: Declaration) throws {
//        switch decl {
//        case let .assignment(variable, declType, expr?):
//            switch expr {
//            case .int(_):
//                /// IDK what to do with these
//                break
//            case .float(_):
//                /// IDK what to do with these
//                break
//            case let .variable(sourceVar):
//                switch sourceVar {
//                case let .simple(sourceName):
//                    switch variable {
//                    case let .simple(targetName):
//                        let source: TensorShape? = env[sourceName]
//                        if declType.shape.count == source?.rank {
//                            env[targetName] = source
//                        } else {
//                            throw SemanticError.typeMismatch
//                        }
//                    default:
//                        /// trying to assign a simple variable to a recurrent variable
//                        break
//                    }
//                case let .recurrent(sourceName, timestep: sourceTimestep, offset: sourceOffset):
//                    let source: TensorShape? = env[sourceName]
//                    switch variable {
//                    case let .recurrent(targetName, timestep: targetTimestep, offset: targetOffset):
//                        //// not sure if this is right
//                        if sourceTimestep == targetTimestep,
//                            sourceOffset  == targetOffset {
//                            env[targetName] = source
//                        } else {
//                            throw SemanticError.typeMismatch
//                        }
//                    default:
//                        /// trying to assign a recurrent variable to a simple variable
//                        break
//                    }
//                }
//
//            case let .add(left, right):
//                switch (left, right) {
//                case let (.variable(l), .variable(r)):
//                    //// result <- l + r
//                    //// match type of result with declType
//                    break
//                default:
//                    throw SemanticError.typeMismatch
//                }
//                
//            case let .mul(left, right):
//                switch (left, right) {
//                case let (.variable(l), .variable(r)):
//                    //// result <- l * r
//                    //// match type of result with declType
//                    break
//                default:
//                    throw SemanticError.typeMismatch
//                }
//                
//            case let .product(left, right):
//                switch (left, right) {
//                case let (.variable(l), .variable(r)):
//                    //// result <- l x r
//                    //// match type of result with declType
//                    break
//                default:
//                    throw SemanticError.typeMismatch
//                }
//                
//            case let .concat(exprs):
//                break
//            default:
//                throw SemanticError.typeMismatch
//            }
//        default: break
//            /// will not happen
//        }
//    }
}
