//
//  TransactionXDR.swift
//  stellarsdk
//
//  Created by SONESO
//  Copyright © 2020 Soneso. All rights reserved.
//

import Foundation

public struct TransactionXDR: XDRCodable {
    public let sourceAccount: MuxedAccountXDR
    public let fee: UInt32
    public let seqNum: Int64
    public let timeBounds: TimeBoundsXDR?
    public let memo: MemoXDR
    public let operations: [OperationXDR]
    public let reserved: Int32
    
    private var signatures = [DecoratedSignatureXDR]()
    
    public init(sourceAccount: PublicKey, seqNum: Int64, timeBounds: TimeBoundsXDR?, memo: MemoXDR, operations: [OperationXDR], maxOperationFee:UInt32 = 100) {
        let mux = MuxedAccountXDR.ed25519(sourceAccount.bytes)
        self.init(sourceAccount: mux, seqNum: seqNum, timeBounds: timeBounds, memo: memo, operations: operations, maxOperationFee: maxOperationFee)
    }
    
    public init(sourceAccount: MuxedAccountXDR, seqNum: Int64, timeBounds: TimeBoundsXDR?, memo: MemoXDR, operations: [OperationXDR], maxOperationFee:UInt32 = 100) {
        self.sourceAccount = sourceAccount
        self.seqNum = seqNum
        self.timeBounds = timeBounds
        self.memo = memo
        self.operations = operations
        
        self.fee = maxOperationFee * UInt32(operations.count)
        
        reserved = 0
    }
    
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        
        sourceAccount = try container.decode(MuxedAccountXDR.self)
        fee = try container.decode(UInt32.self)
        seqNum = try container.decode(Int64.self)
        timeBounds = try decodeArray(type: TimeBoundsXDR.self, dec: decoder).first
        memo = try container.decode(MemoXDR.self)
        operations = try decodeArray(type: OperationXDR.self, dec: decoder)
        reserved = try container.decode(Int32.self)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        
        try container.encode(sourceAccount)
        try container.encode(fee)
        try container.encode(seqNum)
        if let _ = timeBounds {
            try container.encode([timeBounds])
        } else {
            try container.encode([TimeBoundsXDR]())
        }
        try container.encode(memo)
        try container.encode(operations)
        try container.encode(reserved)
    }
    
    public mutating func sign(keyPair:KeyPair, network:Network, coreProtocolVersion:Int?=12) throws {
        let transactionHash = try [UInt8](hash(network: network, coreProtocolVersion: coreProtocolVersion))
        let signature = keyPair.signDecorated(transactionHash)
        signatures.append(signature)
    }
    
    public mutating func addSignature(signature: DecoratedSignatureXDR) {
        signatures.append(signature)
    }
    
    private func signatureBase(network:Network, coreProtocolVersion:Int?=12) throws -> Data {
        
        var pCoreProtocolVersion:Int = 12
        if let pcp = coreProtocolVersion {
            pCoreProtocolVersion = pcp
        }
        
        if (pCoreProtocolVersion < 13) {
            let sourcePublicKey = try PublicKey(accountId: self.sourceAccount.ed25519AccountId)
            let txV0Xdr = TransactionSigV0XDR(sourceAccount: sourcePublicKey, seqNum: self.seqNum, timeBounds: self.timeBounds, memo: self.memo, operations: self.operations)
            let payload = TransactionSignaturePayload(networkId: WrappedData32(network.networkId), taggedTransaction: .typeTXSigV0(txV0Xdr))
            return try Data(bytes: XDREncoder.encode(payload))
        }
        
        let payload = TransactionSignaturePayload(networkId: WrappedData32(network.networkId), taggedTransaction: .typeTX(self))
        return try Data(bytes: XDREncoder.encode(payload))
    }
    
    public func hash(network:Network, coreProtocolVersion:Int?=12) throws -> Data {
        return try signatureBase(network: network, coreProtocolVersion:coreProtocolVersion).sha256()
    }
    
    public func toEnvelopeXDR(coreProtocolVersion:Int?=12) throws -> TransactionEnvelopeXDR {
        guard !signatures.isEmpty else {
            throw StellarSDKError.invalidArgument(message: "Transaction must be signed by at least one signer. Use transaction.sign().")
        }
        var pCoreProtocolVersion:Int = 12
        if let pcp = coreProtocolVersion {
            pCoreProtocolVersion = pcp
        }
        if (pCoreProtocolVersion < 13) {
            let sourcePublicKey = try PublicKey(accountId: self.sourceAccount.ed25519AccountId)
            let txV0Xdr = TransactionV0XDR(sourceAccount: sourcePublicKey, seqNum: self.seqNum, timeBounds: self.timeBounds, memo: self.memo, operations: self.operations)
            let txV0Envelope = TransactionV0EnvelopeXDR(tx: txV0Xdr, signatures: signatures)
            return TransactionEnvelopeXDR.v0(txV0Envelope)
        }
        let envelopeV1 = TransactionV1EnvelopeXDR(tx: self, signatures: signatures)
        return TransactionEnvelopeXDR.v1(envelopeV1)
    }
    
    public func encodedEnvelope(coreProtocolVersion:Int?=12) throws -> String {
        let envelope = try toEnvelopeXDR(coreProtocolVersion:coreProtocolVersion)
        var encodedEnvelope = try XDREncoder.encode(envelope)
        
        return Data(bytes: &encodedEnvelope, count: encodedEnvelope.count).base64EncodedString()
    }
    
    public func toEnvelopeV1XDR() throws -> TransactionV1EnvelopeXDR {
        guard !signatures.isEmpty else {
            throw StellarSDKError.invalidArgument(message: "Transaction must be signed by at least one signer. Use transaction.sign().")
        }
        
        return TransactionV1EnvelopeXDR(tx: self, signatures: signatures)
    }
    
    public func encodedV1Envelope() throws -> String {
        let envelope = try toEnvelopeV1XDR()
        var encodedEnvelope = try XDREncoder.encode(envelope)
        
        return Data(bytes: &encodedEnvelope, count: encodedEnvelope.count).base64EncodedString()
    }
    
    public func encodedV1Transaction() throws -> String {
        var encodedT = try XDREncoder.encode(self)
        
        return Data(bytes: &encodedT, count: encodedT.count).base64EncodedString()
    }
}
