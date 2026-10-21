//
//  SymmetricKey+Extensions.swift
//  NearbyShare
//
//

import Foundation
import CryptoKit

extension SymmetricKey{
	func data() -> Data{
		return withUnsafeBytes({return Data(bytes: $0.baseAddress!, count: $0.count)})
	}
}
