pragma solidity >=0.4.22 <0.6.0;

library G1Caller {
    
    uint256 public constant PRECOMPILE_ADDRESS = 0x9;
    
    event HexPrint(bytes);
    event PrintUint(uint);
    
    enum Operation {
        NoOp,
        G1Add,
        G1Mul,
        G1Multiexp
    }


    struct Caller {
        Operation op;
        bytes inputBuffer;
        uint256 pointer;
        uint8 numPairs;
        uint8 modulusByteLen;
        uint8 groupOrderByteLen;
        bool success;
    }
    
    function initForOp(Caller memory self, Operation opCode, bytes memory baseField, bytes memory groupOrder, uint256 numPairs, bytes memory aCoeff, bytes memory bCoeff) internal 
    pure 
    {
        require(self.op == Operation.NoOp);
        require(opCode != Operation.NoOp);
        uint256 modulusByteLen = baseField.length;
        uint256 groupOrderByteLen = groupOrder.length;
        require(modulusByteLen < 256);
        require(groupOrderByteLen < 256);
        require(numPairs < 256);
        require(aCoeff.length == modulusByteLen);
        require(bCoeff.length == modulusByteLen);
        
        uint256 inputSize = calculateInputSize(opCode, modulusByteLen, groupOrderByteLen, numPairs);
        
        self.op = opCode;
        self.inputBuffer = new bytes(inputSize);
        self.pointer = 0;
        self.numPairs = uint8(numPairs);
        self.modulusByteLen = uint8(modulusByteLen);
        self.groupOrderByteLen = uint8(groupOrderByteLen);
        
        writeByte(self, uint8(self.op));
        writeWithLengthEncoding(self, modulusByteLen, baseField);
        write(self, modulusByteLen, aCoeff);
        write(self, modulusByteLen, bCoeff);
        writeWithLengthEncoding(self, groupOrderByteLen, groupOrder);
    }
    
    function write(Caller memory self, uint256 length, bytes memory data) internal 
    pure 
    {
        require(data.length == length);
        self.pointer = performWrite(self.inputBuffer, self.pointer, data, 0, length);
    }
    
    function performWrite(bytes memory intoBuffer, uint256 intoPointer, bytes memory fromBuffer, uint256 fromPointer, uint256 length) internal 
    pure 
    returns (uint256) {
        require(length > 0);
        require(intoBuffer.length >= intoPointer + length);
        require(fromBuffer.length >= fromPointer + length);
        uint256 dataLen = length;
        uint256 chunks = dataLen / 32;
        if (dataLen % 32 != 0) {
            chunks += 1;
        }
        uint256 inputOffset = fromPointer;
        uint256 pointer = intoPointer;
        bytes32 slice;
        for (uint256 chunk = 0; chunk < chunks; chunk++) {
            assembly {
                slice := mload(add( add(0x20, fromBuffer), inputOffset))
                mstore( add( add(0x20, intoBuffer), pointer), slice )
            }
            if (dataLen <= 32) {
                pointer += dataLen;
                break;
            } else {
                dataLen -= 32;
                pointer += 32;
                inputOffset += 32;
            }
        }
        
        return pointer;
    }
    
    function copyChunk(Caller memory self, bytes memory fromBuffer, uint256 length, uint256 fromOffset) internal 
    pure 
    {
        self.pointer = performWrite(self.inputBuffer, self.pointer, fromBuffer, fromOffset, length);
    }
    
    function writeByte(Caller memory self, uint8 d) internal pure {
        self.pointer = performWriteByte(self.inputBuffer, self.pointer, d);
    }
    
    function performWriteByte(bytes memory intoBuffer, uint256 intoPointer, uint8 d) internal pure returns(uint256) {
        uint256 cast = uint256(d);
        assembly {
            mstore8(add( add(0x20, intoBuffer), intoPointer ), cast)
        }
        return intoPointer + 1;
    }
    
    function writeWithLengthEncoding(Caller memory self, uint256 length, bytes memory data) internal 
    pure 
    {
        uint8 encodedLength = uint8(length);
        writeByte(self, encodedLength);
        write(self, length, data);
    }
    
    function calculateOutputSize(Operation opCode, uint256 modulusByteLen) internal pure returns (uint256) {
        if (opCode == Operation.NoOp) {
            revert();
        } else {
            uint256 len = modulusByteLen * 2;
            return len;
        }
    }

    function calculateInputSize(Operation opCode, uint256 modulusByteLen, uint256 groupOrderByteLen, uint256 numPairs) internal pure returns (uint256) {
        if (opCode == Operation.NoOp) {
            revert();
        } else if (opCode == Operation.G1Add) {
            uint256 len = 1 + 1 + modulusByteLen + 2*uint256(modulusByteLen) + 1 + groupOrderByteLen + 2*modulusByteLen + 2*modulusByteLen;
            return len;
        } else if (opCode == Operation.G1Add) {
            uint256 len = 1 + 1 + modulusByteLen + 2*uint256(modulusByteLen) + 1 + groupOrderByteLen + 2*modulusByteLen + groupOrderByteLen;
            return len;
        } else if (opCode == Operation.G1Multiexp) {
            require(numPairs >= 2);
            uint256 len = 1 + 1 + modulusByteLen + 2*uint256(modulusByteLen) + 1 + groupOrderByteLen + 1 + numPairs * (2*modulusByteLen + groupOrderByteLen);
            return len;
        }
    }
    
    function reuse(Caller memory self, Operation opCode, uint256 numPairs) internal 
    pure 
    {
        require(self.op != Operation.NoOp);
        require(opCode != Operation.NoOp);
        if (self.op != opCode) {
            self.op = opCode;
            uint256 requiredInputLen = calculateInputSize(opCode, uint256(self.modulusByteLen), uint256(self.groupOrderByteLen), numPairs);
            
            if (self.inputBuffer.length < requiredInputLen) {
                bytes memory newInputBuffer = new bytes(requiredInputLen);
                bytes memory oldInputBuffer = self.inputBuffer;
                self.inputBuffer = newInputBuffer;
                writeByte(self, uint8(self.op));
                copyChunk(self, oldInputBuffer, 1 + uint256(self.modulusByteLen) + 1 + uint256(self.groupOrderByteLen) + 2*uint256(self.modulusByteLen), 1);
            } else {
                self.pointer = 1 + 1 + uint256(self.modulusByteLen) + 1 + uint256(self.groupOrderByteLen) + 2*uint256(self.modulusByteLen);
            }
        } else {
            self.pointer = 1 + 1 + uint256(self.modulusByteLen) + 1 + uint256(self.groupOrderByteLen) + 2*uint256(self.modulusByteLen);
        }
    }
    
    function addPoints(Caller memory self, bytes memory a_x, bytes memory a_y, bytes memory b_x, bytes memory b_y) internal 
    // view 
    returns (bytes memory) {
        require(self.op == Operation.G1Add);
        uint256 outputSize = calculateOutputSize(self.op, uint256(self.modulusByteLen));
        bytes memory output = new bytes(outputSize);
        uint256 len = uint256(self.modulusByteLen);
        write(self, len, a_x);
        write(self, len, a_y);
        write(self, len, b_x);
        write(self, len, b_y);
        
        bool success = false;
        
        address callAddress = address(PRECOMPILE_ADDRESS);
        bytes memory buffer = self.inputBuffer;
        uint256 inputDataLen = self.pointer;
        
        emit HexPrint(buffer);
        emit PrintUint(inputDataLen);
        
        // assembly {
        //     success := staticcall(sub(gas(), 2000), callAddress, add(0x20, buffer), inputDataLen, add(0x20, output), outputSize)
        // }
        
        // require(success);
        
        return output;
    }
    
    function mulPoint(Caller memory self, bytes memory a_x, bytes memory a_y, bytes memory scalar) internal 
    // view 
    returns (bytes memory) {
        require(self.op == Operation.G1Mul);
        uint256 outputSize = calculateOutputSize(self.op, uint256(self.modulusByteLen));
        bytes memory output = new bytes(outputSize);
        uint256 len = uint256(self.modulusByteLen);
        write(self, len, a_x);
        write(self, len, a_y);
        write(self, uint256(self.groupOrderByteLen), scalar);
        
        bool success = false;
        
        address callAddress = address(PRECOMPILE_ADDRESS);
        bytes memory buffer = self.inputBuffer;
        uint256 inputDataLen = self.pointer;
        
        emit HexPrint(buffer);
        emit PrintUint(inputDataLen);
        
        // assembly {
        //     success := staticcall(sub(gas(), 2000), callAddress, add(0x20, buffer), inputDataLen, add(0x20, output), outputSize)
        // }
        
        // require(success);
        
        return output;
    }
}

contract G1Test {
    using G1Caller for G1Caller.Caller;
    
    event PrintGas(uint);
    
    bool success = false;
    
    constructor () public {
        
    }
    
    function testAdd() public {
        G1Caller.Caller memory caller = prepare();
        bytes memory a_x = fromHex("0x00");
        bytes memory a_y = fromHex("0x01");
        bytes memory b_x = fromHex("0x05");
        bytes memory b_y = fromHex("0x06");
        
        uint256 g = gasleft();
        
        bytes memory output = caller.addPoints(a_x, a_y, b_x, b_y);
        if (output.length > 0) {
            success = true;
        } else {
            revert();
        }
        
        emit PrintGas(g - gasleft());
        g = gasleft();
        
        caller.reuse(G1Caller.Operation.G1Add, 0);
        output = caller.addPoints(b_x, b_y, a_x, a_y);
        if (output.length > 0) {
            success = true;
        } else {
            revert();
        }
        
        emit PrintGas(g - gasleft());
        g = gasleft();
        
        caller.reuse(G1Caller.Operation.G1Mul, 0);
        caller.mulPoint(b_x, b_y, a_x);
        emit PrintGas(g - gasleft());
    }
    
    function prepare() internal returns (G1Caller.Caller memory) {
        G1Caller.Caller memory caller;
        bytes memory modulus = fromHex("0x11");
        bytes memory group = fromHex("0x10");
        bytes memory a = fromHex("0x00");
        bytes memory b = fromHex("0x03");
        uint256 g = gasleft();
        caller.initForOp(G1Caller.Operation.G1Add, modulus, group, 0, a, b);
        
        emit PrintGas(g - gasleft());
        return caller;
    }
    
    function fromHexChar(uint256 c) private pure returns (uint256) {
        if (byte(uint8(c)) >= byte('0') && byte(uint8(c)) <= byte('9')) {
            return c - uint(uint8(byte('0')));
        }
        if (byte(uint8(c)) >= byte('a') && byte(uint8(c)) <= byte('f')) {
            return 10 + c - uint(uint8(byte('a')));
        }
        if (byte(uint8(c)) >= byte('A') && byte(uint8(c)) <= byte('F')) {
            return 10 + c - uint(uint8(byte('A')));
        }
    }
    
    // Convert an hexadecimal string to raw bytes
    function fromHex(string memory s) private pure returns (bytes memory) {
        bytes memory ss = bytes(s);
        require(ss.length%2 == 0); // length must be even
        bytes memory r = new bytes(ss.length/2 - 1);
        for (uint i=1; i<ss.length/2; ++i) {
            r[i-1] = byte( uint8( fromHexChar( uint(uint8(ss[2*i]) ) ) ) * 16 +
                        uint8( fromHexChar( uint(uint8(ss[2*i+1]) ) ) ) );
        }
        return r;
    }
}