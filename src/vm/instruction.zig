pub const Opcode = enum(u8) {
    // load & store
    /// load integer literal directly into a register
    LOADI,
    /// load value from one register into another
    LOADR,
    /// load value from heap memory
    LOADM,
    /// write value to heap memory
    STOREM,
    /// load a global variable into a register
    LOADG,
    /// store a value in a global variable
    STOREG,

    // arithmetic
    ADD, SUB,
    MUL, DIV, MOD,
    NEG,

    // bitwise
    AND, OR, XOR,
    NOT, SHL, SHR,

    // comparison
    EQ, NE,
    GT, GE,
    LT, LE,

    // control flow
    JMP,
    JE,
    JNE,
    RET,
    RET_VOID,
    CALL,

    // heap memory
    ALLOC, FREE,

    // casting
    ITOF,
    FTOI,
};

/// register instruction
///
/// ex. ADD r1, r2, r3
pub const RInst = packed struct(u32) {
    code: u8,
    dst : u6,
    src1: u6,
    src2: u6,
    _   : u6 = 0,

    pub fn encode(self: RInst) u32 {
        return @bitCast(RInst {
            .code = self.code,
            .dst = self.dst,
            .src1 = self.src1,
            .src2 = self.src2,
        });
    }
};

/// immediate instruction
///
/// ex. LOAD_IMM r1, 42
pub const IInst = packed struct(u32) {
    code: u8,
    dst : u6,
    src : u6,
    imm : i12,

    pub fn encode(self: IInst) u32 {
        return @bitCast(IInst {
            .code = self.code,
            .dst = self.dst,
            .src = self.src,
            .imm = self.imm,
        });
    }
};

/// Jump instructions
///
/// ex. JMP +14
pub const JInst = packed struct(u32) {
    code  : u8,
    dst   : u6,
    offset: i18,

    pub fn encode(self: JInst) u32 {
        return @bitCast(JInst {
            .code = self.code,
            .dst = self.dst,
            .offset = self.offset,
        });
    }
};