//
//  Data+URLSafeBase64.swift
//  Nearby Drop — Created by Arslan Basharat
//
//

import Foundation
import CoreFoundation
import os

extension Data{
	func urlSafeBase64EncodedString() -> String {
		return String(base64EncodedString().replacingOccurrences(of: "=", with: "").map {
			if $0=="/"{
				return "_"
			} else if $0=="+" {
				return "-"
			} else {
				return $0
			}
		})
	}
	
	func suffixOfAtMost(numBytes:Int) -> Data{
		if count<=numBytes{
			return self;
		}
		return subdata(in: count-numBytes..<count)
	}
	
	static func randomData(length: Int) throws -> Data{
		guard length >= 0 else { throw NearbyError.protocolError("Invalid random-data length") }
		var data=Data(count: length)
		let status=data.withUnsafeMutableBytes { bytes in
			guard length == 0 else {
				guard let baseAddress=bytes.baseAddress else { return errSecParam }
				return SecRandomCopyBytes(kSecRandomDefault, length, baseAddress)
			}
			return errSecSuccess
		}
		guard status == errSecSuccess else { throw NearbyError.protocolError("Secure random generation failed") }
		return data
	}
	
	static func dataFromUrlSafeBase64(_ str:String)->Data?{
		var regularB64=String(str.map{
			if $0=="_"{
				return "/"
			}else if $0=="-"{
				return "+"
			}else{
				return $0
			}
		})
		while (regularB64.count%4) != 0{
			regularB64=regularB64+"="
		}
		return Data(base64Encoded: regularB64)
	}

	func hexEncodedString() -> String {
		return map { String(format: "%02x", $0) }.joined()
	}
}

public enum NearbyLogger {
    private static let logger = Logger(subsystem: "com.arslanbasharat.NearByDrop", category: "nearby")

    public static func log(_ message: String) {
        logger.info("\(message, privacy: .private)")
    }
}
