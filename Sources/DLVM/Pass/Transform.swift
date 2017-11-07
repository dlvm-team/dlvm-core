//
//  Transform.swift
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

public extension IRCollection {
    /// Applies a transform pass on self
    ///
    /// - Returns: whether changes are made
    @discardableResult
    func applyTransform<P : TransformPass>(_: P.Type,
                                           bypassingVerification noVerify: Bool = false) -> Bool
        where P.Body == Self
    {
        guard canApplyTransforms else { return false }
        let changed = P.run(on: self)
        if P.shouldInvalidateAnalyses, changed {
            invalidatePassResults()
        }
        /// Run verifier
        if !noVerify {
            do {
                try verify()
            }
            catch {
                fatalError("""
                    Malformed IR after transform \(P.name). This could be caused
                    by not running verification beforehand, or a bug in \(P.name).
                    Verification error:
                    \(error)
                    """)
            }
        }
        return changed
    }
}

public extension IRCollection {
    @discardableResult
    func mapTransform<Transform : TransformPass>(
        _ transform: Transform.Type, bypassingVerification noVerify: Bool = false) -> Bool
        where Transform.Body == Element
    {
        var changed = false
        for element in self {
            changed = element.applyTransform(transform, bypassingVerification: noVerify) || changed
        }
        return changed
    }
    
    @discardableResult
    func mapTransform<Transform : TransformPass>(
        _ transform: Transform.Type, bypassingVerification noVerify: Bool = false) -> Bool
        where Element : IRCollection, Transform.Body == Element.Element
    {
        var changed = false
        for element in self {
            changed = element.mapTransform(transform, bypassingVerification: noVerify) || changed
        }
        return changed
    }
}
