const Operator = @import("blast").Operator;

pub const Opcode = enum(u8) {
    /// load a constant
    LOADC,
    /// load a function
    LOADF,
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
    /// log a certain register to be used for the next function call
    ARG,

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

pub fn OpToCode(op: Operator) ?Opcode {
    return switch (op) {
        .Add => .ADD,
        .Sub => .SUB,
        .Mul => .MUL,
        .Div => .DIV,
        .Mod => .MOD,

        .Eq => .EQ,
        .Neq => .NE,
        .Gt => .GT,
        .Ge => .GE,
        .Lt => .LT,
        .Le => .LE,

        .BitAnd => .AND,
        .BitOr => .OR,
        .BitXor => .XOR,
        .BitNot => .NOT,
        .Lshift => .SHL,
        .Rshift => .SHR,

        else => null,
    };
}

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
    /// meanings based on code:
    /// ```txt
    /// JMP      -> None, it is unused
    /// JE / JNE -> will jump if value in reg is true / false
    /// RET      -> register contains the value to return
    /// CALL     -> value returned by call is stored in reg
    /// LOAD_FN  -> loads a reference to the function into reg
    /// ```
    reg   : u6,
    offset: i18,

    pub fn encode(self: JInst) u32 {
        return @bitCast(JInst {
            .code = self.code,
            .reg = self.reg,
            .offset = self.offset,
        });
    }
};