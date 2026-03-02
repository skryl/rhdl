# frozen_string_literal: true

module RHDL
  module Codegen
    module HIR
      ModuleDef = RHDL::Codegen::IR::ModuleDef
      Port = RHDL::Codegen::IR::Port
      Net = RHDL::Codegen::IR::Net
      Reg = RHDL::Codegen::IR::Reg
      Assign = RHDL::Codegen::IR::Assign
      Process = RHDL::Codegen::IR::Process
      SeqAssign = RHDL::Codegen::IR::SeqAssign
      If = RHDL::Codegen::IR::If
      CaseStmt = RHDL::Codegen::IR::CaseStmt
      CaseBranch = RHDL::Codegen::IR::CaseBranch
      Expr = RHDL::Codegen::IR::Expr
      Signal = RHDL::Codegen::IR::Signal
      Literal = RHDL::Codegen::IR::Literal
      UnaryOp = RHDL::Codegen::IR::UnaryOp
      BinaryOp = RHDL::Codegen::IR::BinaryOp
      Mux = RHDL::Codegen::IR::Mux
      Concat = RHDL::Codegen::IR::Concat
      Slice = RHDL::Codegen::IR::Slice
      Resize = RHDL::Codegen::IR::Resize
      Case = RHDL::Codegen::IR::Case
      MemoryRead = RHDL::Codegen::IR::MemoryRead
      Memory = RHDL::Codegen::IR::Memory
      MemoryWritePort = RHDL::Codegen::IR::MemoryWritePort
      MemorySyncReadPort = RHDL::Codegen::IR::MemorySyncReadPort
      MemoryWrite = RHDL::Codegen::IR::MemoryWrite
      Instance = RHDL::Codegen::IR::Instance
      PortConnection = RHDL::Codegen::IR::PortConnection
    end
  end
end
