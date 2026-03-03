
kernel/kernel:     file format elf32-littleriscv


Disassembly of section .text:

80000000 <_entry>:
80000000:	0000b117          	auipc	sp,0xb
80000004:	40010113          	addi	sp,sp,1024 # 8000b400 <stack0>
80000008:	00001537          	lui	a0,0x1
8000000c:	f14025f3          	csrr	a1,mhartid
80000010:	00158593          	addi	a1,a1,1
80000014:	02b50533          	mul	a0,a0,a1
80000018:	00a10133          	add	sp,sp,a0
8000001c:	0a4000ef          	jal	800000c0 <start>

80000020 <junk>:
80000020:	0000006f          	j	80000020 <junk>

80000024 <timerinit>:
// which arrive at timervec in kernelvec.S,
// which turns them into software interrupts for
// devintr() in trap.c.
void
timerinit()
{
80000024:	ff010113          	addi	sp,sp,-16
80000028:	00112623          	sw	ra,12(sp)
8000002c:	00812423          	sw	s0,8(sp)
80000030:	01010413          	addi	s0,sp,16
// which hart (core) is this?
static inline uint32
r_mhartid()
{
  uint32 x;
  asm volatile("csrr %0, mhartid" : "=r" (x) );
80000034:	f1402673          	csrr	a2,mhartid
  // each CPU has a separate source of timer interrupts.
  int id = r_mhartid();

  // ask the CLINT for a timer interrupt.
  uint32 interval = 1000000; // cycles; about 1/10th second in qemu.
  *(uint64*)CLINT_MTIMECMP(id) = *(uint64*)CLINT_MTIME + interval;
80000038:	004017b7          	lui	a5,0x401
8000003c:	80078793          	addi	a5,a5,-2048 # 400800 <_entry-0x7fbff800>
80000040:	00f607b3          	add	a5,a2,a5
80000044:	00379793          	slli	a5,a5,0x3
80000048:	0200c6b7          	lui	a3,0x200c
8000004c:	ff86a703          	lw	a4,-8(a3) # 200bff8 <_entry-0x7dff4008>
80000050:	ffc6a503          	lw	a0,-4(a3)
80000054:	000f46b7          	lui	a3,0xf4
80000058:	24068693          	addi	a3,a3,576 # f4240 <_entry-0x7ff0bdc0>
8000005c:	00d705b3          	add	a1,a4,a3
80000060:	00e5b733          	sltu	a4,a1,a4
80000064:	00a70733          	add	a4,a4,a0
80000068:	00b7a023          	sw	a1,0(a5)
8000006c:	00e7a223          	sw	a4,4(a5)

  // prepare information in scratch[] for timervec.
  // scratch[0..3] : space for timervec to save registers.
  // scratch[4] : address of CLINT MTIMECMP register.
  // scratch[5] : desired interval (in cycles) between timer interrupts.
  uint32 *scratch = &mscratch0[32 * id];
80000070:	00761613          	slli	a2,a2,0x7
80000074:	0000b717          	auipc	a4,0xb
80000078:	f8c70713          	addi	a4,a4,-116 # 8000b000 <mscratch0>
8000007c:	00c70733          	add	a4,a4,a2
  scratch[4] = CLINT_MTIMECMP(id);
80000080:	00f72823          	sw	a5,16(a4)
  scratch[5] = interval;
80000084:	00d72a23          	sw	a3,20(a4)
}

static inline void 
w_mscratch(uint32 x)
{
  asm volatile("csrw mscratch, %0" : : "r" (x));
80000088:	34071073          	csrw	mscratch,a4
  asm volatile("csrw mtvec, %0" : : "r" (x));
8000008c:	00008797          	auipc	a5,0x8
80000090:	d9478793          	addi	a5,a5,-620 # 80007e20 <timervec>
80000094:	30579073          	csrw	mtvec,a5
  asm volatile("csrr %0, mstatus" : "=r" (x) );
80000098:	300027f3          	csrr	a5,mstatus

  // set the machine-mode trap handler.
  w_mtvec((uint32)timervec);

  // enable machine-mode interrupts.
  w_mstatus(r_mstatus() | MSTATUS_MIE);
8000009c:	0087e793          	ori	a5,a5,8
  asm volatile("csrw mstatus, %0" : : "r" (x));
800000a0:	30079073          	csrw	mstatus,a5
  asm volatile("csrr %0, mie" : "=r" (x) );
800000a4:	304027f3          	csrr	a5,mie

  // enable machine-mode timer interrupts.
  w_mie(r_mie() | MIE_MTIE);
800000a8:	0807e793          	ori	a5,a5,128
  asm volatile("csrw mie, %0" : : "r" (x));
800000ac:	30479073          	csrw	mie,a5
}
800000b0:	00c12083          	lw	ra,12(sp)
800000b4:	00812403          	lw	s0,8(sp)
800000b8:	01010113          	addi	sp,sp,16
800000bc:	00008067          	ret

800000c0 <start>:
{
800000c0:	ff010113          	addi	sp,sp,-16
800000c4:	00112623          	sw	ra,12(sp)
800000c8:	00812423          	sw	s0,8(sp)
800000cc:	01010413          	addi	s0,sp,16
  asm volatile("csrr %0, mstatus" : "=r" (x) );
800000d0:	300027f3          	csrr	a5,mstatus
  x &= ~MSTATUS_MPP_MASK;
800000d4:	ffffe737          	lui	a4,0xffffe
800000d8:	7ff70713          	addi	a4,a4,2047 # ffffe7ff <end+0x7ffda7eb>
800000dc:	00e7f7b3          	and	a5,a5,a4
  x |= MSTATUS_MPP_S;
800000e0:	00001737          	lui	a4,0x1
800000e4:	80070713          	addi	a4,a4,-2048 # 800 <_entry-0x7ffff800>
800000e8:	00e7e7b3          	or	a5,a5,a4
  asm volatile("csrw mstatus, %0" : : "r" (x));
800000ec:	30079073          	csrw	mstatus,a5
  asm volatile("csrw mepc, %0" : : "r" (x));
800000f0:	00001797          	auipc	a5,0x1
800000f4:	15c78793          	addi	a5,a5,348 # 8000124c <main>
800000f8:	34179073          	csrw	mepc,a5
  asm volatile("csrw satp, %0" : : "r" (x));
800000fc:	00000793          	li	a5,0
80000100:	18079073          	csrw	satp,a5
  asm volatile("csrw medeleg, %0" : : "r" (x));
80000104:	000107b7          	lui	a5,0x10
80000108:	fff78793          	addi	a5,a5,-1 # ffff <_entry-0x7fff0001>
8000010c:	30279073          	csrw	medeleg,a5
  asm volatile("csrw mideleg, %0" : : "r" (x));
80000110:	30379073          	csrw	mideleg,a5
  timerinit();
80000114:	00000097          	auipc	ra,0x0
80000118:	f10080e7          	jalr	-240(ra) # 80000024 <timerinit>
  asm volatile("csrr %0, mhartid" : "=r" (x) );
8000011c:	f14027f3          	csrr	a5,mhartid
}

static inline void 
w_tp(uint32 x)
{
  asm volatile("mv tp, %0" : : "r" (x));
80000120:	00078213          	mv	tp,a5
  asm volatile("mret");
80000124:	30200073          	mret
}
80000128:	00c12083          	lw	ra,12(sp)
8000012c:	00812403          	lw	s0,8(sp)
80000130:	01010113          	addi	sp,sp,16
80000134:	00008067          	ret

80000138 <consoleread>:
// user_dist indicates whether dst is a user
// or kernel address.
//
int
consoleread(int user_dst, uint32 dst, int n)
{
80000138:	fc010113          	addi	sp,sp,-64
8000013c:	02112e23          	sw	ra,60(sp)
80000140:	02812c23          	sw	s0,56(sp)
80000144:	02912a23          	sw	s1,52(sp)
80000148:	03212823          	sw	s2,48(sp)
8000014c:	03312623          	sw	s3,44(sp)
80000150:	03412423          	sw	s4,40(sp)
80000154:	03512223          	sw	s5,36(sp)
80000158:	03612023          	sw	s6,32(sp)
8000015c:	04010413          	addi	s0,sp,64
80000160:	00050a93          	mv	s5,a0
80000164:	00058b13          	mv	s6,a1
80000168:	00060993          	mv	s3,a2
  uint target;
  int c;
  char cbuf;

  target = n;
8000016c:	00060a13          	mv	s4,a2
  acquire(&cons.lock);
80000170:	00013517          	auipc	a0,0x13
80000174:	29050513          	addi	a0,a0,656 # 80013400 <cons>
80000178:	00001097          	auipc	ra,0x1
8000017c:	d84080e7          	jalr	-636(ra) # 80000efc <acquire>
  while(n > 0){
    // wait until interrupt handler has put some
    // input into cons.buffer.
    while(cons.r == cons.w){
80000180:	00013497          	auipc	s1,0x13
80000184:	28048493          	addi	s1,s1,640 # 80013400 <cons>
      if(myproc()->killed){
        release(&cons.lock);
        return -1;
      }
      sleep(&cons.r, &cons.lock);
80000188:	00013917          	auipc	s2,0x13
8000018c:	30490913          	addi	s2,s2,772 # 8001348c <cons+0x8c>
  while(n > 0){
80000190:	11305463          	blez	s3,80000298 <consoleread+0x160>
    while(cons.r == cons.w){
80000194:	08c4a783          	lw	a5,140(s1)
80000198:	0904a703          	lw	a4,144(s1)
8000019c:	0ee79463          	bne	a5,a4,80000284 <consoleread+0x14c>
      if(myproc()->killed){
800001a0:	00002097          	auipc	ra,0x2
800001a4:	13c080e7          	jalr	316(ra) # 800022dc <myproc>
800001a8:	01852783          	lw	a5,24(a0)
800001ac:	08079463          	bnez	a5,80000234 <consoleread+0xfc>
      sleep(&cons.r, &cons.lock);
800001b0:	00048593          	mv	a1,s1
800001b4:	00090513          	mv	a0,s2
800001b8:	00003097          	auipc	ra,0x3
800001bc:	b64080e7          	jalr	-1180(ra) # 80002d1c <sleep>
    while(cons.r == cons.w){
800001c0:	08c4a783          	lw	a5,140(s1)
800001c4:	0904a703          	lw	a4,144(s1)
800001c8:	fce78ce3          	beq	a5,a4,800001a0 <consoleread+0x68>
800001cc:	01712e23          	sw	s7,28(sp)
    }

    c = cons.buf[cons.r++ % INPUT_BUF];
800001d0:	00013717          	auipc	a4,0x13
800001d4:	23070713          	addi	a4,a4,560 # 80013400 <cons>
800001d8:	00178693          	addi	a3,a5,1
800001dc:	08d72623          	sw	a3,140(a4)
800001e0:	07f7f693          	andi	a3,a5,127
800001e4:	00d70733          	add	a4,a4,a3
800001e8:	00c74703          	lbu	a4,12(a4)
800001ec:	00070b93          	mv	s7,a4

    if(c == C('D')){  // end-of-file
800001f0:	00400693          	li	a3,4
800001f4:	06d70e63          	beq	a4,a3,80000270 <consoleread+0x138>
800001f8:	016a05b3          	add	a1,s4,s6
      }
      break;
    }

    // copy the input byte to the user-space buffer.
    cbuf = c;
800001fc:	fce407a3          	sb	a4,-49(s0)
    if(either_copyout(user_dst, dst, &cbuf, 1) == -1)
80000200:	00100693          	li	a3,1
80000204:	fcf40613          	addi	a2,s0,-49
80000208:	413585b3          	sub	a1,a1,s3
8000020c:	000a8513          	mv	a0,s5
80000210:	00003097          	auipc	ra,0x3
80000214:	e64080e7          	jalr	-412(ra) # 80003074 <either_copyout>
80000218:	fff00793          	li	a5,-1
8000021c:	06f50c63          	beq	a0,a5,80000294 <consoleread+0x15c>
      break;

    dst++;
    --n;
80000220:	00f989b3          	add	s3,s3,a5

    if(c == '\n'){
80000224:	00a00793          	li	a5,10
80000228:	08fb8463          	beq	s7,a5,800002b0 <consoleread+0x178>
8000022c:	01c12b83          	lw	s7,28(sp)
80000230:	f61ff06f          	j	80000190 <consoleread+0x58>
        release(&cons.lock);
80000234:	00013517          	auipc	a0,0x13
80000238:	1cc50513          	addi	a0,a0,460 # 80013400 <cons>
8000023c:	00001097          	auipc	ra,0x1
80000240:	d34080e7          	jalr	-716(ra) # 80000f70 <release>
        return -1;
80000244:	fff00513          	li	a0,-1
    }
  }
  release(&cons.lock);

  return target - n;
}
80000248:	03c12083          	lw	ra,60(sp)
8000024c:	03812403          	lw	s0,56(sp)
80000250:	03412483          	lw	s1,52(sp)
80000254:	03012903          	lw	s2,48(sp)
80000258:	02c12983          	lw	s3,44(sp)
8000025c:	02812a03          	lw	s4,40(sp)
80000260:	02412a83          	lw	s5,36(sp)
80000264:	02012b03          	lw	s6,32(sp)
80000268:	04010113          	addi	sp,sp,64
8000026c:	00008067          	ret
      if(n < target){
80000270:	0149fe63          	bgeu	s3,s4,8000028c <consoleread+0x154>
        cons.r--;
80000274:	00013717          	auipc	a4,0x13
80000278:	20f72c23          	sw	a5,536(a4) # 8001348c <cons+0x8c>
8000027c:	01c12b83          	lw	s7,28(sp)
80000280:	0180006f          	j	80000298 <consoleread+0x160>
80000284:	01712e23          	sw	s7,28(sp)
80000288:	f49ff06f          	j	800001d0 <consoleread+0x98>
8000028c:	01c12b83          	lw	s7,28(sp)
80000290:	0080006f          	j	80000298 <consoleread+0x160>
80000294:	01c12b83          	lw	s7,28(sp)
  release(&cons.lock);
80000298:	00013517          	auipc	a0,0x13
8000029c:	16850513          	addi	a0,a0,360 # 80013400 <cons>
800002a0:	00001097          	auipc	ra,0x1
800002a4:	cd0080e7          	jalr	-816(ra) # 80000f70 <release>
  return target - n;
800002a8:	413a0533          	sub	a0,s4,s3
800002ac:	f9dff06f          	j	80000248 <consoleread+0x110>
800002b0:	01c12b83          	lw	s7,28(sp)
800002b4:	fe5ff06f          	j	80000298 <consoleread+0x160>

800002b8 <consputc>:
  if(panicked){
800002b8:	00024797          	auipc	a5,0x24
800002bc:	d487a783          	lw	a5,-696(a5) # 80024000 <panicked>
800002c0:	00078463          	beqz	a5,800002c8 <consputc+0x10>
    for(;;)
800002c4:	0000006f          	j	800002c4 <consputc+0xc>
{
800002c8:	ff010113          	addi	sp,sp,-16
800002cc:	00112623          	sw	ra,12(sp)
800002d0:	00812423          	sw	s0,8(sp)
800002d4:	01010413          	addi	s0,sp,16
  if(c == BACKSPACE){
800002d8:	10000793          	li	a5,256
800002dc:	00f50e63          	beq	a0,a5,800002f8 <consputc+0x40>
    uartputc(c);
800002e0:	00000097          	auipc	ra,0x0
800002e4:	7c8080e7          	jalr	1992(ra) # 80000aa8 <uartputc>
}
800002e8:	00c12083          	lw	ra,12(sp)
800002ec:	00812403          	lw	s0,8(sp)
800002f0:	01010113          	addi	sp,sp,16
800002f4:	00008067          	ret
    uartputc('\b'); uartputc(' '); uartputc('\b');
800002f8:	00800513          	li	a0,8
800002fc:	00000097          	auipc	ra,0x0
80000300:	7ac080e7          	jalr	1964(ra) # 80000aa8 <uartputc>
80000304:	02000513          	li	a0,32
80000308:	00000097          	auipc	ra,0x0
8000030c:	7a0080e7          	jalr	1952(ra) # 80000aa8 <uartputc>
80000310:	00800513          	li	a0,8
80000314:	00000097          	auipc	ra,0x0
80000318:	794080e7          	jalr	1940(ra) # 80000aa8 <uartputc>
8000031c:	fcdff06f          	j	800002e8 <consputc+0x30>

80000320 <consolewrite>:
{
80000320:	fc010113          	addi	sp,sp,-64
80000324:	02112e23          	sw	ra,60(sp)
80000328:	02812c23          	sw	s0,56(sp)
8000032c:	02912a23          	sw	s1,52(sp)
80000330:	03212823          	sw	s2,48(sp)
80000334:	01712e23          	sw	s7,28(sp)
80000338:	04010413          	addi	s0,sp,64
8000033c:	00050913          	mv	s2,a0
80000340:	00058493          	mv	s1,a1
80000344:	00060b93          	mv	s7,a2
  acquire(&cons.lock);
80000348:	00013517          	auipc	a0,0x13
8000034c:	0b850513          	addi	a0,a0,184 # 80013400 <cons>
80000350:	00001097          	auipc	ra,0x1
80000354:	bac080e7          	jalr	-1108(ra) # 80000efc <acquire>
  for(i = 0; i < n; i++){
80000358:	07705c63          	blez	s7,800003d0 <consolewrite+0xb0>
8000035c:	03312623          	sw	s3,44(sp)
80000360:	03412423          	sw	s4,40(sp)
80000364:	03512223          	sw	s5,36(sp)
80000368:	03612023          	sw	s6,32(sp)
8000036c:	009b8b33          	add	s6,s7,s1
    if(either_copyin(&c, user_src, src+i, 1) == -1)
80000370:	fcf40a93          	addi	s5,s0,-49
80000374:	00100a13          	li	s4,1
80000378:	fff00993          	li	s3,-1
8000037c:	000a0693          	mv	a3,s4
80000380:	00048613          	mv	a2,s1
80000384:	00090593          	mv	a1,s2
80000388:	000a8513          	mv	a0,s5
8000038c:	00003097          	auipc	ra,0x3
80000390:	d78080e7          	jalr	-648(ra) # 80003104 <either_copyin>
80000394:	03350663          	beq	a0,s3,800003c0 <consolewrite+0xa0>
    consputc(c);
80000398:	fcf44503          	lbu	a0,-49(s0)
8000039c:	00000097          	auipc	ra,0x0
800003a0:	f1c080e7          	jalr	-228(ra) # 800002b8 <consputc>
  for(i = 0; i < n; i++){
800003a4:	00148493          	addi	s1,s1,1
800003a8:	fd649ae3          	bne	s1,s6,8000037c <consolewrite+0x5c>
800003ac:	02c12983          	lw	s3,44(sp)
800003b0:	02812a03          	lw	s4,40(sp)
800003b4:	02412a83          	lw	s5,36(sp)
800003b8:	02012b03          	lw	s6,32(sp)
800003bc:	0140006f          	j	800003d0 <consolewrite+0xb0>
800003c0:	02c12983          	lw	s3,44(sp)
800003c4:	02812a03          	lw	s4,40(sp)
800003c8:	02412a83          	lw	s5,36(sp)
800003cc:	02012b03          	lw	s6,32(sp)
  release(&cons.lock);
800003d0:	00013517          	auipc	a0,0x13
800003d4:	03050513          	addi	a0,a0,48 # 80013400 <cons>
800003d8:	00001097          	auipc	ra,0x1
800003dc:	b98080e7          	jalr	-1128(ra) # 80000f70 <release>
}
800003e0:	000b8513          	mv	a0,s7
800003e4:	03c12083          	lw	ra,60(sp)
800003e8:	03812403          	lw	s0,56(sp)
800003ec:	03412483          	lw	s1,52(sp)
800003f0:	03012903          	lw	s2,48(sp)
800003f4:	01c12b83          	lw	s7,28(sp)
800003f8:	04010113          	addi	sp,sp,64
800003fc:	00008067          	ret

80000400 <consoleintr>:
// do erase/kill processing, append to cons.buf,
// wake up consoleread() if a whole line has arrived.
//
void
consoleintr(int c)
{
80000400:	ff010113          	addi	sp,sp,-16
80000404:	00112623          	sw	ra,12(sp)
80000408:	00812423          	sw	s0,8(sp)
8000040c:	00912223          	sw	s1,4(sp)
80000410:	01010413          	addi	s0,sp,16
80000414:	00050493          	mv	s1,a0
  acquire(&cons.lock);
80000418:	00013517          	auipc	a0,0x13
8000041c:	fe850513          	addi	a0,a0,-24 # 80013400 <cons>
80000420:	00001097          	auipc	ra,0x1
80000424:	adc080e7          	jalr	-1316(ra) # 80000efc <acquire>

  switch(c){
80000428:	01500793          	li	a5,21
8000042c:	0cf48063          	beq	s1,a5,800004ec <consoleintr+0xec>
80000430:	0497c063          	blt	a5,s1,80000470 <consoleintr+0x70>
80000434:	00800793          	li	a5,8
80000438:	12f48063          	beq	s1,a5,80000558 <consoleintr+0x158>
8000043c:	01000793          	li	a5,16
80000440:	14f49463          	bne	s1,a5,80000588 <consoleintr+0x188>
  case C('P'):  // Print process list.
    procdump();
80000444:	00003097          	auipc	ra,0x3
80000448:	d50080e7          	jalr	-688(ra) # 80003194 <procdump>
      }
    }
    break;
  }
  
  release(&cons.lock);
8000044c:	00013517          	auipc	a0,0x13
80000450:	fb450513          	addi	a0,a0,-76 # 80013400 <cons>
80000454:	00001097          	auipc	ra,0x1
80000458:	b1c080e7          	jalr	-1252(ra) # 80000f70 <release>
}
8000045c:	00c12083          	lw	ra,12(sp)
80000460:	00812403          	lw	s0,8(sp)
80000464:	00412483          	lw	s1,4(sp)
80000468:	01010113          	addi	sp,sp,16
8000046c:	00008067          	ret
  switch(c){
80000470:	07f00793          	li	a5,127
80000474:	0ef48263          	beq	s1,a5,80000558 <consoleintr+0x158>
    if(c != 0 && cons.e-cons.r < INPUT_BUF){
80000478:	00013717          	auipc	a4,0x13
8000047c:	f8870713          	addi	a4,a4,-120 # 80013400 <cons>
80000480:	09472783          	lw	a5,148(a4)
80000484:	08c72703          	lw	a4,140(a4)
80000488:	40e787b3          	sub	a5,a5,a4
8000048c:	07f00713          	li	a4,127
80000490:	faf76ee3          	bltu	a4,a5,8000044c <consoleintr+0x4c>
      c = (c == '\r') ? '\n' : c;
80000494:	00d00793          	li	a5,13
80000498:	10f48063          	beq	s1,a5,80000598 <consoleintr+0x198>
      consputc(c);
8000049c:	00048513          	mv	a0,s1
800004a0:	00000097          	auipc	ra,0x0
800004a4:	e18080e7          	jalr	-488(ra) # 800002b8 <consputc>
      cons.buf[cons.e++ % INPUT_BUF] = c;
800004a8:	00013797          	auipc	a5,0x13
800004ac:	f5878793          	addi	a5,a5,-168 # 80013400 <cons>
800004b0:	0947a703          	lw	a4,148(a5)
800004b4:	00170693          	addi	a3,a4,1
800004b8:	08d7aa23          	sw	a3,148(a5)
800004bc:	07f77713          	andi	a4,a4,127
800004c0:	00e787b3          	add	a5,a5,a4
800004c4:	00978623          	sb	s1,12(a5)
      if(c == '\n' || c == C('D') || cons.e == cons.r+INPUT_BUF){
800004c8:	ff648793          	addi	a5,s1,-10
800004cc:	0c078263          	beqz	a5,80000590 <consoleintr+0x190>
800004d0:	ffc48493          	addi	s1,s1,-4
800004d4:	0a048e63          	beqz	s1,80000590 <consoleintr+0x190>
800004d8:	00013797          	auipc	a5,0x13
800004dc:	fb47a783          	lw	a5,-76(a5) # 8001348c <cons+0x8c>
800004e0:	08078793          	addi	a5,a5,128
800004e4:	f6f694e3          	bne	a3,a5,8000044c <consoleintr+0x4c>
800004e8:	0e00006f          	j	800005c8 <consoleintr+0x1c8>
800004ec:	01212023          	sw	s2,0(sp)
    while(cons.e != cons.w &&
800004f0:	00013717          	auipc	a4,0x13
800004f4:	f1070713          	addi	a4,a4,-240 # 80013400 <cons>
800004f8:	09472783          	lw	a5,148(a4)
800004fc:	09072703          	lw	a4,144(a4)
          cons.buf[(cons.e-1) % INPUT_BUF] != '\n'){
80000500:	00013497          	auipc	s1,0x13
80000504:	f0048493          	addi	s1,s1,-256 # 80013400 <cons>
    while(cons.e != cons.w &&
80000508:	00a00913          	li	s2,10
8000050c:	02e78e63          	beq	a5,a4,80000548 <consoleintr+0x148>
          cons.buf[(cons.e-1) % INPUT_BUF] != '\n'){
80000510:	fff78793          	addi	a5,a5,-1
80000514:	07f7f713          	andi	a4,a5,127
80000518:	00e48733          	add	a4,s1,a4
    while(cons.e != cons.w &&
8000051c:	00c74703          	lbu	a4,12(a4)
80000520:	03270863          	beq	a4,s2,80000550 <consoleintr+0x150>
      cons.e--;
80000524:	08f4aa23          	sw	a5,148(s1)
      consputc(BACKSPACE);
80000528:	10000513          	li	a0,256
8000052c:	00000097          	auipc	ra,0x0
80000530:	d8c080e7          	jalr	-628(ra) # 800002b8 <consputc>
    while(cons.e != cons.w &&
80000534:	0944a783          	lw	a5,148(s1)
80000538:	0904a703          	lw	a4,144(s1)
8000053c:	fce79ae3          	bne	a5,a4,80000510 <consoleintr+0x110>
80000540:	00012903          	lw	s2,0(sp)
80000544:	f09ff06f          	j	8000044c <consoleintr+0x4c>
80000548:	00012903          	lw	s2,0(sp)
8000054c:	f01ff06f          	j	8000044c <consoleintr+0x4c>
80000550:	00012903          	lw	s2,0(sp)
80000554:	ef9ff06f          	j	8000044c <consoleintr+0x4c>
    if(cons.e != cons.w){
80000558:	00013717          	auipc	a4,0x13
8000055c:	ea870713          	addi	a4,a4,-344 # 80013400 <cons>
80000560:	09472783          	lw	a5,148(a4)
80000564:	09072703          	lw	a4,144(a4)
80000568:	eee782e3          	beq	a5,a4,8000044c <consoleintr+0x4c>
      cons.e--;
8000056c:	fff78793          	addi	a5,a5,-1
80000570:	00013717          	auipc	a4,0x13
80000574:	f2f72223          	sw	a5,-220(a4) # 80013494 <cons+0x94>
      consputc(BACKSPACE);
80000578:	10000513          	li	a0,256
8000057c:	00000097          	auipc	ra,0x0
80000580:	d3c080e7          	jalr	-708(ra) # 800002b8 <consputc>
80000584:	ec9ff06f          	j	8000044c <consoleintr+0x4c>
    if(c != 0 && cons.e-cons.r < INPUT_BUF){
80000588:	ec0482e3          	beqz	s1,8000044c <consoleintr+0x4c>
8000058c:	eedff06f          	j	80000478 <consoleintr+0x78>
80000590:	00068793          	mv	a5,a3
80000594:	0340006f          	j	800005c8 <consoleintr+0x1c8>
      consputc(c);
80000598:	00a00513          	li	a0,10
8000059c:	00000097          	auipc	ra,0x0
800005a0:	d1c080e7          	jalr	-740(ra) # 800002b8 <consputc>
      cons.buf[cons.e++ % INPUT_BUF] = c;
800005a4:	00013717          	auipc	a4,0x13
800005a8:	e5c70713          	addi	a4,a4,-420 # 80013400 <cons>
800005ac:	09472683          	lw	a3,148(a4)
800005b0:	00168793          	addi	a5,a3,1
800005b4:	08f72a23          	sw	a5,148(a4)
800005b8:	07f6f693          	andi	a3,a3,127
800005bc:	00d70733          	add	a4,a4,a3
800005c0:	00a00693          	li	a3,10
800005c4:	00d70623          	sb	a3,12(a4)
        cons.w = cons.e;
800005c8:	00013717          	auipc	a4,0x13
800005cc:	ecf72423          	sw	a5,-312(a4) # 80013490 <cons+0x90>
        wakeup(&cons.r);
800005d0:	00013517          	auipc	a0,0x13
800005d4:	ebc50513          	addi	a0,a0,-324 # 8001348c <cons+0x8c>
800005d8:	00003097          	auipc	ra,0x3
800005dc:	954080e7          	jalr	-1708(ra) # 80002f2c <wakeup>
800005e0:	e6dff06f          	j	8000044c <consoleintr+0x4c>

800005e4 <consoleinit>:

void
consoleinit(void)
{
800005e4:	ff010113          	addi	sp,sp,-16
800005e8:	00112623          	sw	ra,12(sp)
800005ec:	00812423          	sw	s0,8(sp)
800005f0:	01010413          	addi	s0,sp,16
  initlock(&cons.lock, "cons");
800005f4:	00009597          	auipc	a1,0x9
800005f8:	b3c58593          	addi	a1,a1,-1220 # 80009130 <userret+0x90>
800005fc:	00013517          	auipc	a0,0x13
80000600:	e0450513          	addi	a0,a0,-508 # 80013400 <cons>
80000604:	00000097          	auipc	ra,0x0
80000608:	768080e7          	jalr	1896(ra) # 80000d6c <initlock>

  uartinit();
8000060c:	00000097          	auipc	ra,0x0
80000610:	444080e7          	jalr	1092(ra) # 80000a50 <uartinit>

  // connect read and write system calls
  // to consoleread and consolewrite.
  devsw[CONSOLE].read = consoleread;
80000614:	00020797          	auipc	a5,0x20
80000618:	8c878793          	addi	a5,a5,-1848 # 8001fedc <devsw>
8000061c:	00000717          	auipc	a4,0x0
80000620:	b1c70713          	addi	a4,a4,-1252 # 80000138 <consoleread>
80000624:	00e7a423          	sw	a4,8(a5)
  devsw[CONSOLE].write = consolewrite;
80000628:	00000717          	auipc	a4,0x0
8000062c:	cf870713          	addi	a4,a4,-776 # 80000320 <consolewrite>
80000630:	00e7a623          	sw	a4,12(a5)
}
80000634:	00c12083          	lw	ra,12(sp)
80000638:	00812403          	lw	s0,8(sp)
8000063c:	01010113          	addi	sp,sp,16
80000640:	00008067          	ret

80000644 <printint>:

static char digits[] = "0123456789abcdef";

static void
printint(int xx, int base, int sign)
{
80000644:	fe010113          	addi	sp,sp,-32
80000648:	00112e23          	sw	ra,28(sp)
8000064c:	00812c23          	sw	s0,24(sp)
80000650:	02010413          	addi	s0,sp,32
  char buf[16];
  int i;
  uint x;

  if(sign && (sign = xx < 0))
80000654:	00060463          	beqz	a2,8000065c <printint+0x18>
80000658:	08054c63          	bltz	a0,800006f0 <printint+0xac>
    x = -xx;
  else
    x = xx;
8000065c:	00000313          	li	t1,0

  i = 0;
80000660:	00000793          	li	a5,0
  do {
    buf[i++] = digits[x % base];
80000664:	fe040813          	addi	a6,s0,-32
80000668:	00009617          	auipc	a2,0x9
8000066c:	18460613          	addi	a2,a2,388 # 800097ec <digits>
80000670:	00078893          	mv	a7,a5
80000674:	00178793          	addi	a5,a5,1
80000678:	00f806b3          	add	a3,a6,a5
8000067c:	02b57733          	remu	a4,a0,a1
80000680:	00e60733          	add	a4,a2,a4
80000684:	00074703          	lbu	a4,0(a4)
80000688:	fee68fa3          	sb	a4,-1(a3)
  } while((x /= base) != 0);
8000068c:	00050713          	mv	a4,a0
80000690:	02b55533          	divu	a0,a0,a1
80000694:	fcb77ee3          	bgeu	a4,a1,80000670 <printint+0x2c>

  if(sign)
80000698:	00030c63          	beqz	t1,800006b0 <printint+0x6c>
    buf[i++] = '-';
8000069c:	ff078793          	addi	a5,a5,-16
800006a0:	008787b3          	add	a5,a5,s0
800006a4:	02d00713          	li	a4,45
800006a8:	fee78823          	sb	a4,-16(a5)
800006ac:	00288793          	addi	a5,a7,2

  while(--i >= 0)
800006b0:	02f05863          	blez	a5,800006e0 <printint+0x9c>
800006b4:	00912a23          	sw	s1,20(sp)
800006b8:	01212823          	sw	s2,16(sp)
800006bc:	fe040913          	addi	s2,s0,-32
800006c0:	012784b3          	add	s1,a5,s2
    consputc(buf[i]);
800006c4:	fff4c503          	lbu	a0,-1(s1)
800006c8:	00000097          	auipc	ra,0x0
800006cc:	bf0080e7          	jalr	-1040(ra) # 800002b8 <consputc>
  while(--i >= 0)
800006d0:	fff48493          	addi	s1,s1,-1
800006d4:	ff2498e3          	bne	s1,s2,800006c4 <printint+0x80>
800006d8:	01412483          	lw	s1,20(sp)
800006dc:	01012903          	lw	s2,16(sp)
}
800006e0:	01c12083          	lw	ra,28(sp)
800006e4:	01812403          	lw	s0,24(sp)
800006e8:	02010113          	addi	sp,sp,32
800006ec:	00008067          	ret
    x = -xx;
800006f0:	40a00533          	neg	a0,a0
  if(sign && (sign = xx < 0))
800006f4:	00100313          	li	t1,1
    x = -xx;
800006f8:	f69ff06f          	j	80000660 <printint+0x1c>

800006fc <panic>:
    release(&pr.lock);
}

void
panic(char *s)
{
800006fc:	ff010113          	addi	sp,sp,-16
80000700:	00112623          	sw	ra,12(sp)
80000704:	00812423          	sw	s0,8(sp)
80000708:	00912223          	sw	s1,4(sp)
8000070c:	01010413          	addi	s0,sp,16
80000710:	00050493          	mv	s1,a0
  pr.locking = 0;
80000714:	00013797          	auipc	a5,0x13
80000718:	d807a823          	sw	zero,-624(a5) # 800134a4 <pr+0xc>
  printf("panic: ");
8000071c:	00009517          	auipc	a0,0x9
80000720:	a1c50513          	addi	a0,a0,-1508 # 80009138 <userret+0x98>
80000724:	00000097          	auipc	ra,0x0
80000728:	034080e7          	jalr	52(ra) # 80000758 <printf>
  printf(s);
8000072c:	00048513          	mv	a0,s1
80000730:	00000097          	auipc	ra,0x0
80000734:	028080e7          	jalr	40(ra) # 80000758 <printf>
  printf("\n");
80000738:	00009517          	auipc	a0,0x9
8000073c:	a0850513          	addi	a0,a0,-1528 # 80009140 <userret+0xa0>
80000740:	00000097          	auipc	ra,0x0
80000744:	018080e7          	jalr	24(ra) # 80000758 <printf>
  panicked = 1; // freeze other CPUs
80000748:	00100793          	li	a5,1
8000074c:	00024717          	auipc	a4,0x24
80000750:	8af72a23          	sw	a5,-1868(a4) # 80024000 <panicked>
  for(;;)
80000754:	0000006f          	j	80000754 <panic+0x58>

80000758 <printf>:
{
80000758:	f9010113          	addi	sp,sp,-112
8000075c:	04112623          	sw	ra,76(sp)
80000760:	04812423          	sw	s0,72(sp)
80000764:	03412c23          	sw	s4,56(sp)
80000768:	01b12e23          	sw	s11,28(sp)
8000076c:	05010413          	addi	s0,sp,80
80000770:	00050a13          	mv	s4,a0
80000774:	00b42223          	sw	a1,4(s0)
80000778:	00c42423          	sw	a2,8(s0)
8000077c:	00d42623          	sw	a3,12(s0)
80000780:	00e42823          	sw	a4,16(s0)
80000784:	00f42a23          	sw	a5,20(s0)
80000788:	01042c23          	sw	a6,24(s0)
8000078c:	01142e23          	sw	a7,28(s0)
  locking = pr.locking;
80000790:	00013d97          	auipc	s11,0x13
80000794:	d14dad83          	lw	s11,-748(s11) # 800134a4 <pr+0xc>
  if(locking)
80000798:	060d9063          	bnez	s11,800007f8 <printf+0xa0>
  if (fmt == 0)
8000079c:	060a0863          	beqz	s4,8000080c <printf+0xb4>
  va_start(ap, fmt);
800007a0:	00440793          	addi	a5,s0,4
800007a4:	faf42e23          	sw	a5,-68(s0)
  for(i = 0; (c = fmt[i] & 0xff) != 0; i++){
800007a8:	000a4503          	lbu	a0,0(s4)
800007ac:	20050463          	beqz	a0,800009b4 <printf+0x25c>
800007b0:	04912223          	sw	s1,68(sp)
800007b4:	05212023          	sw	s2,64(sp)
800007b8:	03312e23          	sw	s3,60(sp)
800007bc:	03512a23          	sw	s5,52(sp)
800007c0:	03612823          	sw	s6,48(sp)
800007c4:	03712623          	sw	s7,44(sp)
800007c8:	03812423          	sw	s8,40(sp)
800007cc:	03912223          	sw	s9,36(sp)
800007d0:	03a12023          	sw	s10,32(sp)
800007d4:	00000493          	li	s1,0
    if(c != '%'){
800007d8:	02500a93          	li	s5,37
    switch(c){
800007dc:	07000b13          	li	s6,112
  consputc('x');
800007e0:	07800c93          	li	s9,120
    consputc(digits[x >> (sizeof(uint32) * 8 - 4)]);
800007e4:	00009b97          	auipc	s7,0x9
800007e8:	008b8b93          	addi	s7,s7,8 # 800097ec <digits>
    switch(c){
800007ec:	07300c13          	li	s8,115
      printint(va_arg(ap, int), 16, 1);
800007f0:	00100d13          	li	s10,1
800007f4:	0640006f          	j	80000858 <printf+0x100>
    acquire(&pr.lock);
800007f8:	00013517          	auipc	a0,0x13
800007fc:	ca050513          	addi	a0,a0,-864 # 80013498 <pr>
80000800:	00000097          	auipc	ra,0x0
80000804:	6fc080e7          	jalr	1788(ra) # 80000efc <acquire>
80000808:	f95ff06f          	j	8000079c <printf+0x44>
8000080c:	04912223          	sw	s1,68(sp)
80000810:	05212023          	sw	s2,64(sp)
80000814:	03312e23          	sw	s3,60(sp)
80000818:	03512a23          	sw	s5,52(sp)
8000081c:	03612823          	sw	s6,48(sp)
80000820:	03712623          	sw	s7,44(sp)
80000824:	03812423          	sw	s8,40(sp)
80000828:	03912223          	sw	s9,36(sp)
8000082c:	03a12023          	sw	s10,32(sp)
    panic("null fmt");
80000830:	00009517          	auipc	a0,0x9
80000834:	91c50513          	addi	a0,a0,-1764 # 8000914c <userret+0xac>
80000838:	00000097          	auipc	ra,0x0
8000083c:	ec4080e7          	jalr	-316(ra) # 800006fc <panic>
      consputc(c);
80000840:	00000097          	auipc	ra,0x0
80000844:	a78080e7          	jalr	-1416(ra) # 800002b8 <consputc>
  for(i = 0; (c = fmt[i] & 0xff) != 0; i++){
80000848:	00148493          	addi	s1,s1,1
8000084c:	009a07b3          	add	a5,s4,s1
80000850:	0007c503          	lbu	a0,0(a5)
80000854:	12050e63          	beqz	a0,80000990 <printf+0x238>
    if(c != '%'){
80000858:	ff5514e3          	bne	a0,s5,80000840 <printf+0xe8>
    c = fmt[++i] & 0xff;
8000085c:	00148493          	addi	s1,s1,1
80000860:	009a07b3          	add	a5,s4,s1
80000864:	0007c903          	lbu	s2,0(a5)
    if(c == 0)
80000868:	16090463          	beqz	s2,800009d0 <printf+0x278>
    switch(c){
8000086c:	07690263          	beq	s2,s6,800008d0 <printf+0x178>
80000870:	032b7863          	bgeu	s6,s2,800008a0 <printf+0x148>
80000874:	0b890663          	beq	s2,s8,80000920 <printf+0x1c8>
80000878:	0f991e63          	bne	s2,s9,80000974 <printf+0x21c>
      printint(va_arg(ap, int), 16, 1);
8000087c:	fbc42783          	lw	a5,-68(s0)
80000880:	00478713          	addi	a4,a5,4
80000884:	fae42e23          	sw	a4,-68(s0)
80000888:	000d0613          	mv	a2,s10
8000088c:	01000593          	li	a1,16
80000890:	0007a503          	lw	a0,0(a5)
80000894:	00000097          	auipc	ra,0x0
80000898:	db0080e7          	jalr	-592(ra) # 80000644 <printint>
      break;
8000089c:	fadff06f          	j	80000848 <printf+0xf0>
    switch(c){
800008a0:	0d590263          	beq	s2,s5,80000964 <printf+0x20c>
800008a4:	06400793          	li	a5,100
800008a8:	0cf91663          	bne	s2,a5,80000974 <printf+0x21c>
      printint(va_arg(ap, int), 10, 1);
800008ac:	fbc42783          	lw	a5,-68(s0)
800008b0:	00478713          	addi	a4,a5,4
800008b4:	fae42e23          	sw	a4,-68(s0)
800008b8:	000d0613          	mv	a2,s10
800008bc:	00a00593          	li	a1,10
800008c0:	0007a503          	lw	a0,0(a5)
800008c4:	00000097          	auipc	ra,0x0
800008c8:	d80080e7          	jalr	-640(ra) # 80000644 <printint>
      break;
800008cc:	f7dff06f          	j	80000848 <printf+0xf0>
      printptr(va_arg(ap, uint32));
800008d0:	fbc42783          	lw	a5,-68(s0)
800008d4:	00478713          	addi	a4,a5,4
800008d8:	fae42e23          	sw	a4,-68(s0)
800008dc:	0007a983          	lw	s3,0(a5)
  consputc('0');
800008e0:	03000513          	li	a0,48
800008e4:	00000097          	auipc	ra,0x0
800008e8:	9d4080e7          	jalr	-1580(ra) # 800002b8 <consputc>
  consputc('x');
800008ec:	000c8513          	mv	a0,s9
800008f0:	00000097          	auipc	ra,0x0
800008f4:	9c8080e7          	jalr	-1592(ra) # 800002b8 <consputc>
800008f8:	00800913          	li	s2,8
    consputc(digits[x >> (sizeof(uint32) * 8 - 4)]);
800008fc:	01c9d793          	srli	a5,s3,0x1c
80000900:	00fb87b3          	add	a5,s7,a5
80000904:	0007c503          	lbu	a0,0(a5)
80000908:	00000097          	auipc	ra,0x0
8000090c:	9b0080e7          	jalr	-1616(ra) # 800002b8 <consputc>
  for (i = 0; i < (sizeof(uint32) * 2); i++, x <<= 4)
80000910:	00499993          	slli	s3,s3,0x4
80000914:	fff90913          	addi	s2,s2,-1
80000918:	fe0912e3          	bnez	s2,800008fc <printf+0x1a4>
8000091c:	f2dff06f          	j	80000848 <printf+0xf0>
      if((s = va_arg(ap, char*)) == 0)
80000920:	fbc42783          	lw	a5,-68(s0)
80000924:	00478713          	addi	a4,a5,4
80000928:	fae42e23          	sw	a4,-68(s0)
8000092c:	0007a903          	lw	s2,0(a5)
80000930:	02090263          	beqz	s2,80000954 <printf+0x1fc>
      for(; *s; s++)
80000934:	00094503          	lbu	a0,0(s2)
80000938:	f00508e3          	beqz	a0,80000848 <printf+0xf0>
        consputc(*s);
8000093c:	00000097          	auipc	ra,0x0
80000940:	97c080e7          	jalr	-1668(ra) # 800002b8 <consputc>
      for(; *s; s++)
80000944:	00190913          	addi	s2,s2,1
80000948:	00094503          	lbu	a0,0(s2)
8000094c:	fe0518e3          	bnez	a0,8000093c <printf+0x1e4>
80000950:	ef9ff06f          	j	80000848 <printf+0xf0>
        s = "(null)";
80000954:	00008917          	auipc	s2,0x8
80000958:	7f090913          	addi	s2,s2,2032 # 80009144 <userret+0xa4>
      for(; *s; s++)
8000095c:	02800513          	li	a0,40
80000960:	fddff06f          	j	8000093c <printf+0x1e4>
      consputc('%');
80000964:	000a8513          	mv	a0,s5
80000968:	00000097          	auipc	ra,0x0
8000096c:	950080e7          	jalr	-1712(ra) # 800002b8 <consputc>
      break;
80000970:	ed9ff06f          	j	80000848 <printf+0xf0>
      consputc('%');
80000974:	000a8513          	mv	a0,s5
80000978:	00000097          	auipc	ra,0x0
8000097c:	940080e7          	jalr	-1728(ra) # 800002b8 <consputc>
      consputc(c);
80000980:	00090513          	mv	a0,s2
80000984:	00000097          	auipc	ra,0x0
80000988:	934080e7          	jalr	-1740(ra) # 800002b8 <consputc>
      break;
8000098c:	ebdff06f          	j	80000848 <printf+0xf0>
80000990:	04412483          	lw	s1,68(sp)
80000994:	04012903          	lw	s2,64(sp)
80000998:	03c12983          	lw	s3,60(sp)
8000099c:	03412a83          	lw	s5,52(sp)
800009a0:	03012b03          	lw	s6,48(sp)
800009a4:	02c12b83          	lw	s7,44(sp)
800009a8:	02812c03          	lw	s8,40(sp)
800009ac:	02412c83          	lw	s9,36(sp)
800009b0:	02012d03          	lw	s10,32(sp)
  if(locking)
800009b4:	040d9263          	bnez	s11,800009f8 <printf+0x2a0>
}
800009b8:	04c12083          	lw	ra,76(sp)
800009bc:	04812403          	lw	s0,72(sp)
800009c0:	03812a03          	lw	s4,56(sp)
800009c4:	01c12d83          	lw	s11,28(sp)
800009c8:	07010113          	addi	sp,sp,112
800009cc:	00008067          	ret
800009d0:	04412483          	lw	s1,68(sp)
800009d4:	04012903          	lw	s2,64(sp)
800009d8:	03c12983          	lw	s3,60(sp)
800009dc:	03412a83          	lw	s5,52(sp)
800009e0:	03012b03          	lw	s6,48(sp)
800009e4:	02c12b83          	lw	s7,44(sp)
800009e8:	02812c03          	lw	s8,40(sp)
800009ec:	02412c83          	lw	s9,36(sp)
800009f0:	02012d03          	lw	s10,32(sp)
800009f4:	fc1ff06f          	j	800009b4 <printf+0x25c>
    release(&pr.lock);
800009f8:	00013517          	auipc	a0,0x13
800009fc:	aa050513          	addi	a0,a0,-1376 # 80013498 <pr>
80000a00:	00000097          	auipc	ra,0x0
80000a04:	570080e7          	jalr	1392(ra) # 80000f70 <release>
}
80000a08:	fb1ff06f          	j	800009b8 <printf+0x260>

80000a0c <printfinit>:
    ;
}

void
printfinit(void)
{
80000a0c:	ff010113          	addi	sp,sp,-16
80000a10:	00112623          	sw	ra,12(sp)
80000a14:	00812423          	sw	s0,8(sp)
80000a18:	01010413          	addi	s0,sp,16
  initlock(&pr.lock, "pr");
80000a1c:	00008597          	auipc	a1,0x8
80000a20:	73c58593          	addi	a1,a1,1852 # 80009158 <userret+0xb8>
80000a24:	00013517          	auipc	a0,0x13
80000a28:	a7450513          	addi	a0,a0,-1420 # 80013498 <pr>
80000a2c:	00000097          	auipc	ra,0x0
80000a30:	340080e7          	jalr	832(ra) # 80000d6c <initlock>
  pr.locking = 1;
80000a34:	00100793          	li	a5,1
80000a38:	00013717          	auipc	a4,0x13
80000a3c:	a6f72623          	sw	a5,-1428(a4) # 800134a4 <pr+0xc>
}
80000a40:	00c12083          	lw	ra,12(sp)
80000a44:	00812403          	lw	s0,8(sp)
80000a48:	01010113          	addi	sp,sp,16
80000a4c:	00008067          	ret

80000a50 <uartinit>:
#define ReadReg(reg) (*(Reg(reg)))
#define WriteReg(reg, v) (*(Reg(reg)) = (v))

void
uartinit(void)
{
80000a50:	ff010113          	addi	sp,sp,-16
80000a54:	00112623          	sw	ra,12(sp)
80000a58:	00812423          	sw	s0,8(sp)
80000a5c:	01010413          	addi	s0,sp,16
  // disable interrupts.
  WriteReg(IER, 0x00);
80000a60:	100007b7          	lui	a5,0x10000
80000a64:	000780a3          	sb	zero,1(a5) # 10000001 <_entry-0x6fffffff>

  // special mode to set baud rate.
  WriteReg(LCR, 0x80);
80000a68:	10000737          	lui	a4,0x10000
80000a6c:	f8000693          	li	a3,-128
80000a70:	00d701a3          	sb	a3,3(a4) # 10000003 <_entry-0x6ffffffd>

  // LSB for baud rate of 38.4K.
  WriteReg(0, 0x03);
80000a74:	00300693          	li	a3,3
80000a78:	10000637          	lui	a2,0x10000
80000a7c:	00d60023          	sb	a3,0(a2) # 10000000 <_entry-0x70000000>

  // MSB for baud rate of 38.4K.
  WriteReg(1, 0x00);
80000a80:	000780a3          	sb	zero,1(a5)

  // leave set-baud mode,
  // and set word length to 8 bits, no parity.
  WriteReg(LCR, 0x03);
80000a84:	00d701a3          	sb	a3,3(a4)

  // reset and enable FIFOs.
  WriteReg(FCR, 0x07);
80000a88:	00700693          	li	a3,7
80000a8c:	00d60123          	sb	a3,2(a2)

  // enable receive interrupts.
  WriteReg(IER, 0x01);
80000a90:	00100713          	li	a4,1
80000a94:	00e780a3          	sb	a4,1(a5)
}
80000a98:	00c12083          	lw	ra,12(sp)
80000a9c:	00812403          	lw	s0,8(sp)
80000aa0:	01010113          	addi	sp,sp,16
80000aa4:	00008067          	ret

80000aa8 <uartputc>:

// write one output character to the UART.
void
uartputc(int c)
{
80000aa8:	ff010113          	addi	sp,sp,-16
80000aac:	00112623          	sw	ra,12(sp)
80000ab0:	00812423          	sw	s0,8(sp)
80000ab4:	01010413          	addi	s0,sp,16
  // wait for Transmit Holding Empty to be set in LSR.
  while((ReadReg(LSR) & (1 << 5)) == 0)
80000ab8:	10000737          	lui	a4,0x10000
80000abc:	00570713          	addi	a4,a4,5 # 10000005 <_entry-0x6ffffffb>
80000ac0:	00074783          	lbu	a5,0(a4)
80000ac4:	0207f793          	andi	a5,a5,32
80000ac8:	fe078ce3          	beqz	a5,80000ac0 <uartputc+0x18>
    ;
  WriteReg(THR, c);
80000acc:	0ff57513          	zext.b	a0,a0
80000ad0:	100007b7          	lui	a5,0x10000
80000ad4:	00a78023          	sb	a0,0(a5) # 10000000 <_entry-0x70000000>
}
80000ad8:	00c12083          	lw	ra,12(sp)
80000adc:	00812403          	lw	s0,8(sp)
80000ae0:	01010113          	addi	sp,sp,16
80000ae4:	00008067          	ret

80000ae8 <uartgetc>:

// read one input character from the UART.
// return -1 if none is waiting.
int
uartgetc(void)
{
80000ae8:	ff010113          	addi	sp,sp,-16
80000aec:	00112623          	sw	ra,12(sp)
80000af0:	00812423          	sw	s0,8(sp)
80000af4:	01010413          	addi	s0,sp,16
  if(ReadReg(LSR) & 0x01){
80000af8:	100007b7          	lui	a5,0x10000
80000afc:	0057c783          	lbu	a5,5(a5) # 10000005 <_entry-0x6ffffffb>
80000b00:	0017f793          	andi	a5,a5,1
80000b04:	02078063          	beqz	a5,80000b24 <uartgetc+0x3c>
    // input data is ready.
    return ReadReg(RHR);
80000b08:	100007b7          	lui	a5,0x10000
80000b0c:	0007c503          	lbu	a0,0(a5) # 10000000 <_entry-0x70000000>
80000b10:	0ff57513          	zext.b	a0,a0
  } else {
    return -1;
  }
}
80000b14:	00c12083          	lw	ra,12(sp)
80000b18:	00812403          	lw	s0,8(sp)
80000b1c:	01010113          	addi	sp,sp,16
80000b20:	00008067          	ret
    return -1;
80000b24:	fff00513          	li	a0,-1
80000b28:	fedff06f          	j	80000b14 <uartgetc+0x2c>

80000b2c <uartintr>:

// trap.c calls here when the uart interrupts.
void
uartintr(void)
{
80000b2c:	ff010113          	addi	sp,sp,-16
80000b30:	00112623          	sw	ra,12(sp)
80000b34:	00812423          	sw	s0,8(sp)
80000b38:	00912223          	sw	s1,4(sp)
80000b3c:	01010413          	addi	s0,sp,16
  while(1){
    int c = uartgetc();
    if(c == -1)
80000b40:	fff00493          	li	s1,-1
    int c = uartgetc();
80000b44:	00000097          	auipc	ra,0x0
80000b48:	fa4080e7          	jalr	-92(ra) # 80000ae8 <uartgetc>
    if(c == -1)
80000b4c:	00950863          	beq	a0,s1,80000b5c <uartintr+0x30>
      break;
    consoleintr(c);
80000b50:	00000097          	auipc	ra,0x0
80000b54:	8b0080e7          	jalr	-1872(ra) # 80000400 <consoleintr>
  while(1){
80000b58:	fedff06f          	j	80000b44 <uartintr+0x18>
  }
}
80000b5c:	00c12083          	lw	ra,12(sp)
80000b60:	00812403          	lw	s0,8(sp)
80000b64:	00412483          	lw	s1,4(sp)
80000b68:	01010113          	addi	sp,sp,16
80000b6c:	00008067          	ret

80000b70 <kfree>:
// which normally should have been returned by a
// call to kalloc().  (The exception is when
// initializing the allocator; see kinit above.)
void
kfree(void *pa)
{
80000b70:	ff010113          	addi	sp,sp,-16
80000b74:	00112623          	sw	ra,12(sp)
80000b78:	00812423          	sw	s0,8(sp)
80000b7c:	00912223          	sw	s1,4(sp)
80000b80:	01212023          	sw	s2,0(sp)
80000b84:	01010413          	addi	s0,sp,16
  struct run *r;

  if(((uint32)pa % PGSIZE) != 0 || (char*)pa < end || (uint32)pa >= PHYSTOP)
80000b88:	00023797          	auipc	a5,0x23
80000b8c:	48c78793          	addi	a5,a5,1164 # 80024014 <end>
80000b90:	00f537b3          	sltu	a5,a0,a5
80000b94:	88000737          	lui	a4,0x88000
80000b98:	00e53733          	sltu	a4,a0,a4
80000b9c:	00173713          	seqz	a4,a4
80000ba0:	00e7e7b3          	or	a5,a5,a4
80000ba4:	06079263          	bnez	a5,80000c08 <kfree+0x98>
80000ba8:	00050493          	mv	s1,a0
80000bac:	01451793          	slli	a5,a0,0x14
80000bb0:	04079c63          	bnez	a5,80000c08 <kfree+0x98>
    panic("kfree");

  // Fill with junk to catch dangling refs.
  memset(pa, 1, PGSIZE);
80000bb4:	00001637          	lui	a2,0x1
80000bb8:	00100593          	li	a1,1
80000bbc:	00000097          	auipc	ra,0x0
80000bc0:	414080e7          	jalr	1044(ra) # 80000fd0 <memset>

  r = (struct run*)pa;

  acquire(&kmem.lock);
80000bc4:	00013917          	auipc	s2,0x13
80000bc8:	8e490913          	addi	s2,s2,-1820 # 800134a8 <kmem>
80000bcc:	00090513          	mv	a0,s2
80000bd0:	00000097          	auipc	ra,0x0
80000bd4:	32c080e7          	jalr	812(ra) # 80000efc <acquire>
  r->next = kmem.freelist;
80000bd8:	00c92783          	lw	a5,12(s2)
80000bdc:	00f4a023          	sw	a5,0(s1)
  kmem.freelist = r;
80000be0:	00992623          	sw	s1,12(s2)
  release(&kmem.lock);
80000be4:	00090513          	mv	a0,s2
80000be8:	00000097          	auipc	ra,0x0
80000bec:	388080e7          	jalr	904(ra) # 80000f70 <release>
}
80000bf0:	00c12083          	lw	ra,12(sp)
80000bf4:	00812403          	lw	s0,8(sp)
80000bf8:	00412483          	lw	s1,4(sp)
80000bfc:	00012903          	lw	s2,0(sp)
80000c00:	01010113          	addi	sp,sp,16
80000c04:	00008067          	ret
    panic("kfree");
80000c08:	00008517          	auipc	a0,0x8
80000c0c:	55450513          	addi	a0,a0,1364 # 8000915c <userret+0xbc>
80000c10:	00000097          	auipc	ra,0x0
80000c14:	aec080e7          	jalr	-1300(ra) # 800006fc <panic>

80000c18 <freerange>:
{
80000c18:	fe010113          	addi	sp,sp,-32
80000c1c:	00112e23          	sw	ra,28(sp)
80000c20:	00812c23          	sw	s0,24(sp)
80000c24:	00912a23          	sw	s1,20(sp)
80000c28:	02010413          	addi	s0,sp,32
  p = (char*)PGROUNDUP((uint32)pa_start);
80000c2c:	000017b7          	lui	a5,0x1
80000c30:	fff78713          	addi	a4,a5,-1 # fff <_entry-0x7ffff001>
80000c34:	00e504b3          	add	s1,a0,a4
80000c38:	fffff737          	lui	a4,0xfffff
80000c3c:	00e4f4b3          	and	s1,s1,a4
  for(; p + PGSIZE <= (char*)pa_end; p += PGSIZE) {
80000c40:	00f484b3          	add	s1,s1,a5
80000c44:	0295ee63          	bltu	a1,s1,80000c80 <freerange+0x68>
80000c48:	01212823          	sw	s2,16(sp)
80000c4c:	01312623          	sw	s3,12(sp)
80000c50:	01412423          	sw	s4,8(sp)
80000c54:	00058913          	mv	s2,a1
    kfree(p);
80000c58:	00070a13          	mv	s4,a4
  for(; p + PGSIZE <= (char*)pa_end; p += PGSIZE) {
80000c5c:	00078993          	mv	s3,a5
    kfree(p);
80000c60:	01448533          	add	a0,s1,s4
80000c64:	00000097          	auipc	ra,0x0
80000c68:	f0c080e7          	jalr	-244(ra) # 80000b70 <kfree>
  for(; p + PGSIZE <= (char*)pa_end; p += PGSIZE) {
80000c6c:	013484b3          	add	s1,s1,s3
80000c70:	fe9978e3          	bgeu	s2,s1,80000c60 <freerange+0x48>
80000c74:	01012903          	lw	s2,16(sp)
80000c78:	00c12983          	lw	s3,12(sp)
80000c7c:	00812a03          	lw	s4,8(sp)
}
80000c80:	01c12083          	lw	ra,28(sp)
80000c84:	01812403          	lw	s0,24(sp)
80000c88:	01412483          	lw	s1,20(sp)
80000c8c:	02010113          	addi	sp,sp,32
80000c90:	00008067          	ret

80000c94 <kinit>:
{
80000c94:	ff010113          	addi	sp,sp,-16
80000c98:	00112623          	sw	ra,12(sp)
80000c9c:	00812423          	sw	s0,8(sp)
80000ca0:	01010413          	addi	s0,sp,16
  initlock(&kmem.lock, "kmem");
80000ca4:	00008597          	auipc	a1,0x8
80000ca8:	4c058593          	addi	a1,a1,1216 # 80009164 <userret+0xc4>
80000cac:	00012517          	auipc	a0,0x12
80000cb0:	7fc50513          	addi	a0,a0,2044 # 800134a8 <kmem>
80000cb4:	00000097          	auipc	ra,0x0
80000cb8:	0b8080e7          	jalr	184(ra) # 80000d6c <initlock>
  freerange(end, (void*)PHYSTOP);
80000cbc:	880005b7          	lui	a1,0x88000
80000cc0:	00023517          	auipc	a0,0x23
80000cc4:	35450513          	addi	a0,a0,852 # 80024014 <end>
80000cc8:	00000097          	auipc	ra,0x0
80000ccc:	f50080e7          	jalr	-176(ra) # 80000c18 <freerange>
}
80000cd0:	00c12083          	lw	ra,12(sp)
80000cd4:	00812403          	lw	s0,8(sp)
80000cd8:	01010113          	addi	sp,sp,16
80000cdc:	00008067          	ret

80000ce0 <kalloc>:
// Allocate one 4096-byte page of physical memory.
// Returns a pointer that the kernel can use.
// Returns 0 if the memory cannot be allocated.
void *
kalloc(void)
{
80000ce0:	ff010113          	addi	sp,sp,-16
80000ce4:	00112623          	sw	ra,12(sp)
80000ce8:	00812423          	sw	s0,8(sp)
80000cec:	00912223          	sw	s1,4(sp)
80000cf0:	01010413          	addi	s0,sp,16
  struct run *r;

  acquire(&kmem.lock);
80000cf4:	00012517          	auipc	a0,0x12
80000cf8:	7b450513          	addi	a0,a0,1972 # 800134a8 <kmem>
80000cfc:	00000097          	auipc	ra,0x0
80000d00:	200080e7          	jalr	512(ra) # 80000efc <acquire>
  r = kmem.freelist;
80000d04:	00012497          	auipc	s1,0x12
80000d08:	7b04a483          	lw	s1,1968(s1) # 800134b4 <kmem+0xc>
  if(r)
80000d0c:	04048663          	beqz	s1,80000d58 <kalloc+0x78>
    kmem.freelist = r->next;
80000d10:	0004a783          	lw	a5,0(s1)
80000d14:	00012717          	auipc	a4,0x12
80000d18:	7af72023          	sw	a5,1952(a4) # 800134b4 <kmem+0xc>
  release(&kmem.lock);
80000d1c:	00012517          	auipc	a0,0x12
80000d20:	78c50513          	addi	a0,a0,1932 # 800134a8 <kmem>
80000d24:	00000097          	auipc	ra,0x0
80000d28:	24c080e7          	jalr	588(ra) # 80000f70 <release>

  if(r)
    memset((char*)r, 5, PGSIZE); // fill with junk
80000d2c:	00001637          	lui	a2,0x1
80000d30:	00500593          	li	a1,5
80000d34:	00048513          	mv	a0,s1
80000d38:	00000097          	auipc	ra,0x0
80000d3c:	298080e7          	jalr	664(ra) # 80000fd0 <memset>
  return (void*)r;
}
80000d40:	00048513          	mv	a0,s1
80000d44:	00c12083          	lw	ra,12(sp)
80000d48:	00812403          	lw	s0,8(sp)
80000d4c:	00412483          	lw	s1,4(sp)
80000d50:	01010113          	addi	sp,sp,16
80000d54:	00008067          	ret
  release(&kmem.lock);
80000d58:	00012517          	auipc	a0,0x12
80000d5c:	75050513          	addi	a0,a0,1872 # 800134a8 <kmem>
80000d60:	00000097          	auipc	ra,0x0
80000d64:	210080e7          	jalr	528(ra) # 80000f70 <release>
  if(r)
80000d68:	fd9ff06f          	j	80000d40 <kalloc+0x60>

80000d6c <initlock>:
#include "proc.h"
#include "defs.h"

void
initlock(struct spinlock *lk, char *name)
{
80000d6c:	ff010113          	addi	sp,sp,-16
80000d70:	00112623          	sw	ra,12(sp)
80000d74:	00812423          	sw	s0,8(sp)
80000d78:	01010413          	addi	s0,sp,16
  lk->name = name;
80000d7c:	00b52223          	sw	a1,4(a0)
  lk->locked = 0;
80000d80:	00052023          	sw	zero,0(a0)
  lk->cpu = 0;
80000d84:	00052423          	sw	zero,8(a0)
}
80000d88:	00c12083          	lw	ra,12(sp)
80000d8c:	00812403          	lw	s0,8(sp)
80000d90:	01010113          	addi	sp,sp,16
80000d94:	00008067          	ret

80000d98 <push_off>:
// it takes two pop_off()s to undo two push_off()s.  Also, if interrupts
// are initially off, then push_off, pop_off leaves them off.

void
push_off(void)
{
80000d98:	ff010113          	addi	sp,sp,-16
80000d9c:	00112623          	sw	ra,12(sp)
80000da0:	00812423          	sw	s0,8(sp)
80000da4:	00912223          	sw	s1,4(sp)
80000da8:	01010413          	addi	s0,sp,16
  asm volatile("csrr %0, sstatus" : "=r" (x) );
80000dac:	100027f3          	csrr	a5,sstatus
80000db0:	00078493          	mv	s1,a5
80000db4:	100027f3          	csrr	a5,sstatus
  w_sstatus(r_sstatus() & ~SSTATUS_SIE);
80000db8:	ffd7f793          	andi	a5,a5,-3
  asm volatile("csrw sstatus, %0" : : "r" (x));
80000dbc:	10079073          	csrw	sstatus,a5
  int old = intr_get();

  intr_off();
  if(mycpu()->noff == 0)
80000dc0:	00001097          	auipc	ra,0x1
80000dc4:	4e0080e7          	jalr	1248(ra) # 800022a0 <mycpu>
80000dc8:	03c52783          	lw	a5,60(a0)
80000dcc:	02078663          	beqz	a5,80000df8 <push_off+0x60>
    mycpu()->intena = old;
  mycpu()->noff += 1;
80000dd0:	00001097          	auipc	ra,0x1
80000dd4:	4d0080e7          	jalr	1232(ra) # 800022a0 <mycpu>
80000dd8:	03c52783          	lw	a5,60(a0)
80000ddc:	00178793          	addi	a5,a5,1
80000de0:	02f52e23          	sw	a5,60(a0)
}
80000de4:	00c12083          	lw	ra,12(sp)
80000de8:	00812403          	lw	s0,8(sp)
80000dec:	00412483          	lw	s1,4(sp)
80000df0:	01010113          	addi	sp,sp,16
80000df4:	00008067          	ret
    mycpu()->intena = old;
80000df8:	00001097          	auipc	ra,0x1
80000dfc:	4a8080e7          	jalr	1192(ra) # 800022a0 <mycpu>
  return (x & SSTATUS_SIE) != 0;
80000e00:	0014d793          	srli	a5,s1,0x1
80000e04:	0017f793          	andi	a5,a5,1
80000e08:	04f52023          	sw	a5,64(a0)
80000e0c:	fc5ff06f          	j	80000dd0 <push_off+0x38>

80000e10 <pop_off>:

void
pop_off(void)
{
80000e10:	ff010113          	addi	sp,sp,-16
80000e14:	00112623          	sw	ra,12(sp)
80000e18:	00812423          	sw	s0,8(sp)
80000e1c:	01010413          	addi	s0,sp,16
  struct cpu *c = mycpu();
80000e20:	00001097          	auipc	ra,0x1
80000e24:	480080e7          	jalr	1152(ra) # 800022a0 <mycpu>
  asm volatile("csrr %0, sstatus" : "=r" (x) );
80000e28:	100027f3          	csrr	a5,sstatus
  return (x & SSTATUS_SIE) != 0;
80000e2c:	0027f793          	andi	a5,a5,2
  if(intr_get())
80000e30:	04079463          	bnez	a5,80000e78 <pop_off+0x68>
    panic("pop_off - interruptible");
  c->noff -= 1;
80000e34:	03c52783          	lw	a5,60(a0)
80000e38:	fff78793          	addi	a5,a5,-1
80000e3c:	02f52e23          	sw	a5,60(a0)
  if(c->noff < 0)
80000e40:	0407c463          	bltz	a5,80000e88 <pop_off+0x78>
    panic("pop_off");
  if(c->noff == 0 && c->intena)
80000e44:	02079263          	bnez	a5,80000e68 <pop_off+0x58>
80000e48:	04052783          	lw	a5,64(a0)
80000e4c:	00078e63          	beqz	a5,80000e68 <pop_off+0x58>
  asm volatile("csrr %0, sie" : "=r" (x) );
80000e50:	104027f3          	csrr	a5,sie
  w_sie(r_sie() | SIE_SEIE | SIE_STIE | SIE_SSIE);
80000e54:	2227e793          	ori	a5,a5,546
  asm volatile("csrw sie, %0" : : "r" (x));
80000e58:	10479073          	csrw	sie,a5
  asm volatile("csrr %0, sstatus" : "=r" (x) );
80000e5c:	100027f3          	csrr	a5,sstatus
  w_sstatus(r_sstatus() | SSTATUS_SIE);
80000e60:	0027e793          	ori	a5,a5,2
  asm volatile("csrw sstatus, %0" : : "r" (x));
80000e64:	10079073          	csrw	sstatus,a5
    intr_on();
}
80000e68:	00c12083          	lw	ra,12(sp)
80000e6c:	00812403          	lw	s0,8(sp)
80000e70:	01010113          	addi	sp,sp,16
80000e74:	00008067          	ret
    panic("pop_off - interruptible");
80000e78:	00008517          	auipc	a0,0x8
80000e7c:	2f450513          	addi	a0,a0,756 # 8000916c <userret+0xcc>
80000e80:	00000097          	auipc	ra,0x0
80000e84:	87c080e7          	jalr	-1924(ra) # 800006fc <panic>
    panic("pop_off");
80000e88:	00008517          	auipc	a0,0x8
80000e8c:	2fc50513          	addi	a0,a0,764 # 80009184 <userret+0xe4>
80000e90:	00000097          	auipc	ra,0x0
80000e94:	86c080e7          	jalr	-1940(ra) # 800006fc <panic>

80000e98 <holding>:
{
80000e98:	ff010113          	addi	sp,sp,-16
80000e9c:	00112623          	sw	ra,12(sp)
80000ea0:	00812423          	sw	s0,8(sp)
80000ea4:	00912223          	sw	s1,4(sp)
80000ea8:	01010413          	addi	s0,sp,16
80000eac:	00050493          	mv	s1,a0
  push_off();
80000eb0:	00000097          	auipc	ra,0x0
80000eb4:	ee8080e7          	jalr	-280(ra) # 80000d98 <push_off>
  r = (lk->locked && lk->cpu == mycpu());
80000eb8:	0004a783          	lw	a5,0(s1)
80000ebc:	02079463          	bnez	a5,80000ee4 <holding+0x4c>
80000ec0:	00000493          	li	s1,0
  pop_off();
80000ec4:	00000097          	auipc	ra,0x0
80000ec8:	f4c080e7          	jalr	-180(ra) # 80000e10 <pop_off>
}
80000ecc:	00048513          	mv	a0,s1
80000ed0:	00c12083          	lw	ra,12(sp)
80000ed4:	00812403          	lw	s0,8(sp)
80000ed8:	00412483          	lw	s1,4(sp)
80000edc:	01010113          	addi	sp,sp,16
80000ee0:	00008067          	ret
  r = (lk->locked && lk->cpu == mycpu());
80000ee4:	0084a483          	lw	s1,8(s1)
80000ee8:	00001097          	auipc	ra,0x1
80000eec:	3b8080e7          	jalr	952(ra) # 800022a0 <mycpu>
80000ef0:	40a484b3          	sub	s1,s1,a0
80000ef4:	0014b493          	seqz	s1,s1
80000ef8:	fcdff06f          	j	80000ec4 <holding+0x2c>

80000efc <acquire>:
{
80000efc:	ff010113          	addi	sp,sp,-16
80000f00:	00112623          	sw	ra,12(sp)
80000f04:	00812423          	sw	s0,8(sp)
80000f08:	00912223          	sw	s1,4(sp)
80000f0c:	01010413          	addi	s0,sp,16
80000f10:	00050493          	mv	s1,a0
  push_off(); // disable interrupts to avoid deadlock.
80000f14:	00000097          	auipc	ra,0x0
80000f18:	e84080e7          	jalr	-380(ra) # 80000d98 <push_off>
  if(holding(lk))
80000f1c:	00048513          	mv	a0,s1
80000f20:	00000097          	auipc	ra,0x0
80000f24:	f78080e7          	jalr	-136(ra) # 80000e98 <holding>
  while(__sync_lock_test_and_set(&lk->locked, 1) != 0)
80000f28:	00100713          	li	a4,1
  if(holding(lk))
80000f2c:	02051a63          	bnez	a0,80000f60 <acquire+0x64>
  while(__sync_lock_test_and_set(&lk->locked, 1) != 0)
80000f30:	00070793          	mv	a5,a4
80000f34:	0cf4a7af          	amoswap.w.aq	a5,a5,(s1)
80000f38:	fe079ce3          	bnez	a5,80000f30 <acquire+0x34>
  __sync_synchronize();
80000f3c:	0330000f          	fence	rw,rw
  lk->cpu = mycpu();
80000f40:	00001097          	auipc	ra,0x1
80000f44:	360080e7          	jalr	864(ra) # 800022a0 <mycpu>
80000f48:	00a4a423          	sw	a0,8(s1)
}
80000f4c:	00c12083          	lw	ra,12(sp)
80000f50:	00812403          	lw	s0,8(sp)
80000f54:	00412483          	lw	s1,4(sp)
80000f58:	01010113          	addi	sp,sp,16
80000f5c:	00008067          	ret
    panic("acquire");
80000f60:	00008517          	auipc	a0,0x8
80000f64:	22c50513          	addi	a0,a0,556 # 8000918c <userret+0xec>
80000f68:	fffff097          	auipc	ra,0xfffff
80000f6c:	794080e7          	jalr	1940(ra) # 800006fc <panic>

80000f70 <release>:
{
80000f70:	ff010113          	addi	sp,sp,-16
80000f74:	00112623          	sw	ra,12(sp)
80000f78:	00812423          	sw	s0,8(sp)
80000f7c:	00912223          	sw	s1,4(sp)
80000f80:	01010413          	addi	s0,sp,16
80000f84:	00050493          	mv	s1,a0
  if(!holding(lk))
80000f88:	00000097          	auipc	ra,0x0
80000f8c:	f10080e7          	jalr	-240(ra) # 80000e98 <holding>
80000f90:	02050863          	beqz	a0,80000fc0 <release+0x50>
  lk->cpu = 0;
80000f94:	0004a423          	sw	zero,8(s1)
  __sync_synchronize();
80000f98:	0330000f          	fence	rw,rw
  __sync_lock_release(&lk->locked);
80000f9c:	0310000f          	fence	rw,w
80000fa0:	0004a023          	sw	zero,0(s1)
  pop_off();
80000fa4:	00000097          	auipc	ra,0x0
80000fa8:	e6c080e7          	jalr	-404(ra) # 80000e10 <pop_off>
}
80000fac:	00c12083          	lw	ra,12(sp)
80000fb0:	00812403          	lw	s0,8(sp)
80000fb4:	00412483          	lw	s1,4(sp)
80000fb8:	01010113          	addi	sp,sp,16
80000fbc:	00008067          	ret
    panic("release");
80000fc0:	00008517          	auipc	a0,0x8
80000fc4:	1d450513          	addi	a0,a0,468 # 80009194 <userret+0xf4>
80000fc8:	fffff097          	auipc	ra,0xfffff
80000fcc:	734080e7          	jalr	1844(ra) # 800006fc <panic>

80000fd0 <memset>:
#include "types.h"

void*
memset(void *dst, int c, uint n)
{
80000fd0:	ff010113          	addi	sp,sp,-16
80000fd4:	00112623          	sw	ra,12(sp)
80000fd8:	00812423          	sw	s0,8(sp)
80000fdc:	01010413          	addi	s0,sp,16
  char *cdst = (char *) dst;
  int i;
  for(i = 0; i < n; i++){
80000fe0:	00060c63          	beqz	a2,80000ff8 <memset+0x28>
80000fe4:	00050793          	mv	a5,a0
80000fe8:	00a60633          	add	a2,a2,a0
    cdst[i] = c;
80000fec:	00b78023          	sb	a1,0(a5)
  for(i = 0; i < n; i++){
80000ff0:	00178793          	addi	a5,a5,1
80000ff4:	fec79ce3          	bne	a5,a2,80000fec <memset+0x1c>
  }
  return dst;
}
80000ff8:	00c12083          	lw	ra,12(sp)
80000ffc:	00812403          	lw	s0,8(sp)
80001000:	01010113          	addi	sp,sp,16
80001004:	00008067          	ret

80001008 <memcmp>:

int
memcmp(const void *v1, const void *v2, uint n)
{
80001008:	ff010113          	addi	sp,sp,-16
8000100c:	00112623          	sw	ra,12(sp)
80001010:	00812423          	sw	s0,8(sp)
80001014:	01010413          	addi	s0,sp,16
  const uchar *s1, *s2;

  s1 = v1;
  s2 = v2;
  while(n-- > 0){
80001018:	02060e63          	beqz	a2,80001054 <memcmp+0x4c>
8000101c:	00c50633          	add	a2,a0,a2
    if(*s1 != *s2)
80001020:	00054783          	lbu	a5,0(a0)
80001024:	0005c703          	lbu	a4,0(a1) # 88000000 <end+0x7fdbfec>
80001028:	00e79c63          	bne	a5,a4,80001040 <memcmp+0x38>
      return *s1 - *s2;
    s1++, s2++;
8000102c:	00150513          	addi	a0,a0,1
80001030:	00158593          	addi	a1,a1,1
  while(n-- > 0){
80001034:	fea616e3          	bne	a2,a0,80001020 <memcmp+0x18>
  }

  return 0;
80001038:	00000513          	li	a0,0
8000103c:	0080006f          	j	80001044 <memcmp+0x3c>
      return *s1 - *s2;
80001040:	40e78533          	sub	a0,a5,a4
}
80001044:	00c12083          	lw	ra,12(sp)
80001048:	00812403          	lw	s0,8(sp)
8000104c:	01010113          	addi	sp,sp,16
80001050:	00008067          	ret
  return 0;
80001054:	00000513          	li	a0,0
80001058:	fedff06f          	j	80001044 <memcmp+0x3c>

8000105c <memmove>:

void*
memmove(void *dst, const void *src, uint n)
{
8000105c:	ff010113          	addi	sp,sp,-16
80001060:	00112623          	sw	ra,12(sp)
80001064:	00812423          	sw	s0,8(sp)
80001068:	01010413          	addi	s0,sp,16
  const char *s;
  char *d;

  s = src;
  d = dst;
  if(s < d && s + n > d){
8000106c:	02a5ea63          	bltu	a1,a0,800010a0 <memmove+0x44>
    s += n;
    d += n;
    while(n-- > 0)
      *--d = *--s;
  } else
    while(n-- > 0)
80001070:	00c586b3          	add	a3,a1,a2
80001074:	00050793          	mv	a5,a0
80001078:	00060c63          	beqz	a2,80001090 <memmove+0x34>
      *d++ = *s++;
8000107c:	00158593          	addi	a1,a1,1
80001080:	00178793          	addi	a5,a5,1
80001084:	fff5c703          	lbu	a4,-1(a1)
80001088:	fee78fa3          	sb	a4,-1(a5)
    while(n-- > 0)
8000108c:	fed598e3          	bne	a1,a3,8000107c <memmove+0x20>

  return dst;
}
80001090:	00c12083          	lw	ra,12(sp)
80001094:	00812403          	lw	s0,8(sp)
80001098:	01010113          	addi	sp,sp,16
8000109c:	00008067          	ret
  if(s < d && s + n > d){
800010a0:	00c58733          	add	a4,a1,a2
800010a4:	fce576e3          	bgeu	a0,a4,80001070 <memmove+0x14>
    while(n-- > 0)
800010a8:	fe0604e3          	beqz	a2,80001090 <memmove+0x34>
    d += n;
800010ac:	00c507b3          	add	a5,a0,a2
      *--d = *--s;
800010b0:	fff70713          	addi	a4,a4,-1
800010b4:	fff78793          	addi	a5,a5,-1
800010b8:	00074683          	lbu	a3,0(a4)
800010bc:	00d78023          	sb	a3,0(a5)
    while(n-- > 0)
800010c0:	fee598e3          	bne	a1,a4,800010b0 <memmove+0x54>
800010c4:	fcdff06f          	j	80001090 <memmove+0x34>

800010c8 <memcpy>:

// memcpy exists to placate GCC.  Use memmove.
void*
memcpy(void *dst, const void *src, uint n)
{
800010c8:	ff010113          	addi	sp,sp,-16
800010cc:	00112623          	sw	ra,12(sp)
800010d0:	00812423          	sw	s0,8(sp)
800010d4:	01010413          	addi	s0,sp,16
  return memmove(dst, src, n);
800010d8:	00000097          	auipc	ra,0x0
800010dc:	f84080e7          	jalr	-124(ra) # 8000105c <memmove>
}
800010e0:	00c12083          	lw	ra,12(sp)
800010e4:	00812403          	lw	s0,8(sp)
800010e8:	01010113          	addi	sp,sp,16
800010ec:	00008067          	ret

800010f0 <strncmp>:

int
strncmp(const char *p, const char *q, uint n)
{
800010f0:	ff010113          	addi	sp,sp,-16
800010f4:	00112623          	sw	ra,12(sp)
800010f8:	00812423          	sw	s0,8(sp)
800010fc:	01010413          	addi	s0,sp,16
  while(n > 0 && *p && *p == *q)
80001100:	02060663          	beqz	a2,8000112c <strncmp+0x3c>
80001104:	00054783          	lbu	a5,0(a0)
80001108:	02078663          	beqz	a5,80001134 <strncmp+0x44>
8000110c:	0005c703          	lbu	a4,0(a1)
80001110:	02f71263          	bne	a4,a5,80001134 <strncmp+0x44>
    n--, p++, q++;
80001114:	fff60613          	addi	a2,a2,-1 # fff <_entry-0x7ffff001>
80001118:	00150513          	addi	a0,a0,1
8000111c:	00158593          	addi	a1,a1,1
  while(n > 0 && *p && *p == *q)
80001120:	fe0612e3          	bnez	a2,80001104 <strncmp+0x14>
  if(n == 0)
    return 0;
80001124:	00000513          	li	a0,0
80001128:	0180006f          	j	80001140 <strncmp+0x50>
8000112c:	00000513          	li	a0,0
80001130:	0100006f          	j	80001140 <strncmp+0x50>
  return (uchar)*p - (uchar)*q;
80001134:	00054503          	lbu	a0,0(a0)
80001138:	0005c783          	lbu	a5,0(a1)
8000113c:	40f50533          	sub	a0,a0,a5
}
80001140:	00c12083          	lw	ra,12(sp)
80001144:	00812403          	lw	s0,8(sp)
80001148:	01010113          	addi	sp,sp,16
8000114c:	00008067          	ret

80001150 <strncpy>:

char*
strncpy(char *s, const char *t, int n)
{
80001150:	ff010113          	addi	sp,sp,-16
80001154:	00112623          	sw	ra,12(sp)
80001158:	00812423          	sw	s0,8(sp)
8000115c:	01010413          	addi	s0,sp,16
  char *os;

  os = s;
  while(n-- > 0 && (*s++ = *t++) != 0)
80001160:	00050793          	mv	a5,a0
80001164:	0080006f          	j	8000116c <strncpy+0x1c>
80001168:	00068613          	mv	a2,a3
8000116c:	02c05e63          	blez	a2,800011a8 <strncpy+0x58>
80001170:	fff60693          	addi	a3,a2,-1
80001174:	00158593          	addi	a1,a1,1
80001178:	00178793          	addi	a5,a5,1
8000117c:	fff5c703          	lbu	a4,-1(a1)
80001180:	fee78fa3          	sb	a4,-1(a5)
80001184:	fe0712e3          	bnez	a4,80001168 <strncpy+0x18>
    ;
  while(n-- > 0)
80001188:	00078713          	mv	a4,a5
8000118c:	00c787b3          	add	a5,a5,a2
80001190:	fff78793          	addi	a5,a5,-1
80001194:	00d05a63          	blez	a3,800011a8 <strncpy+0x58>
    *s++ = 0;
80001198:	00170713          	addi	a4,a4,1
8000119c:	fe070fa3          	sb	zero,-1(a4)
  while(n-- > 0)
800011a0:	40e786b3          	sub	a3,a5,a4
800011a4:	fed04ae3          	bgtz	a3,80001198 <strncpy+0x48>
  return os;
}
800011a8:	00c12083          	lw	ra,12(sp)
800011ac:	00812403          	lw	s0,8(sp)
800011b0:	01010113          	addi	sp,sp,16
800011b4:	00008067          	ret

800011b8 <safestrcpy>:

// Like strncpy but guaranteed to NUL-terminate.
char*
safestrcpy(char *s, const char *t, int n)
{
800011b8:	ff010113          	addi	sp,sp,-16
800011bc:	00112623          	sw	ra,12(sp)
800011c0:	00812423          	sw	s0,8(sp)
800011c4:	01010413          	addi	s0,sp,16
  char *os;

  os = s;
  if(n <= 0)
800011c8:	02c05663          	blez	a2,800011f4 <safestrcpy+0x3c>
800011cc:	fff60613          	addi	a2,a2,-1
800011d0:	00c586b3          	add	a3,a1,a2
800011d4:	00050793          	mv	a5,a0
    return os;
  while(--n > 0 && (*s++ = *t++) != 0)
800011d8:	00d58c63          	beq	a1,a3,800011f0 <safestrcpy+0x38>
800011dc:	00158593          	addi	a1,a1,1
800011e0:	00178793          	addi	a5,a5,1
800011e4:	fff5c703          	lbu	a4,-1(a1)
800011e8:	fee78fa3          	sb	a4,-1(a5)
800011ec:	fe0716e3          	bnez	a4,800011d8 <safestrcpy+0x20>
    ;
  *s = 0;
800011f0:	00078023          	sb	zero,0(a5)
  return os;
}
800011f4:	00c12083          	lw	ra,12(sp)
800011f8:	00812403          	lw	s0,8(sp)
800011fc:	01010113          	addi	sp,sp,16
80001200:	00008067          	ret

80001204 <strlen>:

int
strlen(const char *s)
{
80001204:	ff010113          	addi	sp,sp,-16
80001208:	00112623          	sw	ra,12(sp)
8000120c:	00812423          	sw	s0,8(sp)
80001210:	01010413          	addi	s0,sp,16
  int n;

  for(n = 0; s[n]; n++)
80001214:	00054783          	lbu	a5,0(a0)
80001218:	02078663          	beqz	a5,80001244 <strlen+0x40>
8000121c:	00050713          	mv	a4,a0
80001220:	00000513          	li	a0,0
80001224:	00150513          	addi	a0,a0,1
80001228:	00a707b3          	add	a5,a4,a0
8000122c:	0007c783          	lbu	a5,0(a5)
80001230:	fe079ae3          	bnez	a5,80001224 <strlen+0x20>
    ;
  return n;
}
80001234:	00c12083          	lw	ra,12(sp)
80001238:	00812403          	lw	s0,8(sp)
8000123c:	01010113          	addi	sp,sp,16
80001240:	00008067          	ret
  for(n = 0; s[n]; n++)
80001244:	00000513          	li	a0,0
  return n;
80001248:	fedff06f          	j	80001234 <strlen+0x30>

8000124c <main>:
volatile static int started = 0;

// start() jumps here in supervisor mode on all CPUs.
void
main()
{
8000124c:	ff010113          	addi	sp,sp,-16
80001250:	00112623          	sw	ra,12(sp)
80001254:	00812423          	sw	s0,8(sp)
80001258:	01010413          	addi	s0,sp,16
  if(cpuid() == 0){
8000125c:	00001097          	auipc	ra,0x1
80001260:	020080e7          	jalr	32(ra) # 8000227c <cpuid>
    virtio_disk_init(); // emulated hard disk
    userinit();      // first user process
    __sync_synchronize();
    started = 1;
  } else {
    while(started == 0)
80001264:	00023717          	auipc	a4,0x23
80001268:	da070713          	addi	a4,a4,-608 # 80024004 <started>
  if(cpuid() == 0){
8000126c:	04050663          	beqz	a0,800012b8 <main+0x6c>
    while(started == 0)
80001270:	00072783          	lw	a5,0(a4)
80001274:	fe078ee3          	beqz	a5,80001270 <main+0x24>
      ;
    __sync_synchronize();
80001278:	0330000f          	fence	rw,rw
    printf("hart %d starting\n", cpuid());
8000127c:	00001097          	auipc	ra,0x1
80001280:	000080e7          	jalr	ra # 8000227c <cpuid>
80001284:	00050593          	mv	a1,a0
80001288:	00008517          	auipc	a0,0x8
8000128c:	f2c50513          	addi	a0,a0,-212 # 800091b4 <userret+0x114>
80001290:	fffff097          	auipc	ra,0xfffff
80001294:	4c8080e7          	jalr	1224(ra) # 80000758 <printf>
    kvminithart();    // turn on paging
80001298:	00000097          	auipc	ra,0x0
8000129c:	240080e7          	jalr	576(ra) # 800014d8 <kvminithart>
    trapinithart();   // install kernel trap vector
800012a0:	00002097          	auipc	ra,0x2
800012a4:	090080e7          	jalr	144(ra) # 80003330 <trapinithart>
    plicinithart();   // ask PLIC for device interrupts
800012a8:	00007097          	auipc	ra,0x7
800012ac:	c08080e7          	jalr	-1016(ra) # 80007eb0 <plicinithart>
  }

  scheduler();        
800012b0:	00001097          	auipc	ra,0x1
800012b4:	6d8080e7          	jalr	1752(ra) # 80002988 <scheduler>
    consoleinit();
800012b8:	fffff097          	auipc	ra,0xfffff
800012bc:	32c080e7          	jalr	812(ra) # 800005e4 <consoleinit>
    printfinit();
800012c0:	fffff097          	auipc	ra,0xfffff
800012c4:	74c080e7          	jalr	1868(ra) # 80000a0c <printfinit>
    printf("\n");
800012c8:	00008517          	auipc	a0,0x8
800012cc:	e7850513          	addi	a0,a0,-392 # 80009140 <userret+0xa0>
800012d0:	fffff097          	auipc	ra,0xfffff
800012d4:	488080e7          	jalr	1160(ra) # 80000758 <printf>
    printf("xv6 kernel is booting\n");
800012d8:	00008517          	auipc	a0,0x8
800012dc:	ec450513          	addi	a0,a0,-316 # 8000919c <userret+0xfc>
800012e0:	fffff097          	auipc	ra,0xfffff
800012e4:	478080e7          	jalr	1144(ra) # 80000758 <printf>
    printf("\n");
800012e8:	00008517          	auipc	a0,0x8
800012ec:	e5850513          	addi	a0,a0,-424 # 80009140 <userret+0xa0>
800012f0:	fffff097          	auipc	ra,0xfffff
800012f4:	468080e7          	jalr	1128(ra) # 80000758 <printf>
    kinit();         // physical page allocator
800012f8:	00000097          	auipc	ra,0x0
800012fc:	99c080e7          	jalr	-1636(ra) # 80000c94 <kinit>
    kvminit();       // create kernel page table
80001300:	00000097          	auipc	ra,0x0
80001304:	434080e7          	jalr	1076(ra) # 80001734 <kvminit>
    kvminithart();   // turn on paging
80001308:	00000097          	auipc	ra,0x0
8000130c:	1d0080e7          	jalr	464(ra) # 800014d8 <kvminithart>
    procinit();      // process table
80001310:	00001097          	auipc	ra,0x1
80001314:	e4c080e7          	jalr	-436(ra) # 8000215c <procinit>
    trapinit();      // trap vectors
80001318:	00002097          	auipc	ra,0x2
8000131c:	fe0080e7          	jalr	-32(ra) # 800032f8 <trapinit>
    trapinithart();  // install kernel trap vector
80001320:	00002097          	auipc	ra,0x2
80001324:	010080e7          	jalr	16(ra) # 80003330 <trapinithart>
    plicinit();      // set up interrupt controller
80001328:	00007097          	auipc	ra,0x7
8000132c:	b58080e7          	jalr	-1192(ra) # 80007e80 <plicinit>
    plicinithart();  // ask PLIC for device interrupts
80001330:	00007097          	auipc	ra,0x7
80001334:	b80080e7          	jalr	-1152(ra) # 80007eb0 <plicinithart>
    binit();         // buffer cache
80001338:	00003097          	auipc	ra,0x3
8000133c:	a44080e7          	jalr	-1468(ra) # 80003d7c <binit>
    iinit();         // inode cache
80001340:	00003097          	auipc	ra,0x3
80001344:	2d0080e7          	jalr	720(ra) # 80004610 <iinit>
    fileinit();      // file table
80001348:	00005097          	auipc	ra,0x5
8000134c:	898080e7          	jalr	-1896(ra) # 80005be0 <fileinit>
    virtio_disk_init(); // emulated hard disk
80001350:	00007097          	auipc	ra,0x7
80001354:	d00080e7          	jalr	-768(ra) # 80008050 <virtio_disk_init>
    userinit();      // first user process
80001358:	00001097          	auipc	ra,0x1
8000135c:	2f8080e7          	jalr	760(ra) # 80002650 <userinit>
    __sync_synchronize();
80001360:	0330000f          	fence	rw,rw
    started = 1;
80001364:	00100793          	li	a5,1
80001368:	00023717          	auipc	a4,0x23
8000136c:	c8f72e23          	sw	a5,-868(a4) # 80024004 <started>
80001370:	f41ff06f          	j	800012b0 <main+0x64>

80001374 <walk>:
//    0.. 7 -- flags: Valid/Read/Write/Execute/User/Global/Accessed/Dirty
// 

static pte_t *
walk(pagetable_t pagetable, uint32 va, int alloc)
{
80001374:	fe010113          	addi	sp,sp,-32
80001378:	00112e23          	sw	ra,28(sp)
8000137c:	00812c23          	sw	s0,24(sp)
80001380:	00912a23          	sw	s1,20(sp)
80001384:	01212823          	sw	s2,16(sp)
80001388:	01312623          	sw	s3,12(sp)
8000138c:	02010413          	addi	s0,sp,32
  if(va >= MAXVA)
80001390:	fff00793          	li	a5,-1
80001394:	04f58c63          	beq	a1,a5,800013ec <walk+0x78>
80001398:	00058493          	mv	s1,a1
    panic("walk");

  for(int level = 1; level > 0; level--) {
    pte_t *pte = &pagetable[PX(level, va)];
8000139c:	0165d793          	srli	a5,a1,0x16
800013a0:	00279793          	slli	a5,a5,0x2
800013a4:	00f509b3          	add	s3,a0,a5
    if(*pte & PTE_V) {
800013a8:	0009a903          	lw	s2,0(s3)
800013ac:	00197793          	andi	a5,s2,1
800013b0:	04078663          	beqz	a5,800013fc <walk+0x88>
      pagetable = (pagetable_t)PTE2PA(*pte);
800013b4:	00a95913          	srli	s2,s2,0xa
800013b8:	00c91913          	slli	s2,s2,0xc
        return 0;
      memset(pagetable, 0, PGSIZE);
      *pte = PA2PTE(pagetable) | PTE_V;
    }
  }
  return &pagetable[PX(0, va)];
800013bc:	00c4d493          	srli	s1,s1,0xc
800013c0:	3ff4f493          	andi	s1,s1,1023
800013c4:	00249493          	slli	s1,s1,0x2
800013c8:	00990933          	add	s2,s2,s1
}
800013cc:	00090513          	mv	a0,s2
800013d0:	01c12083          	lw	ra,28(sp)
800013d4:	01812403          	lw	s0,24(sp)
800013d8:	01412483          	lw	s1,20(sp)
800013dc:	01012903          	lw	s2,16(sp)
800013e0:	00c12983          	lw	s3,12(sp)
800013e4:	02010113          	addi	sp,sp,32
800013e8:	00008067          	ret
    panic("walk");
800013ec:	00008517          	auipc	a0,0x8
800013f0:	ddc50513          	addi	a0,a0,-548 # 800091c8 <userret+0x128>
800013f4:	fffff097          	auipc	ra,0xfffff
800013f8:	308080e7          	jalr	776(ra) # 800006fc <panic>
      if(!alloc || (pagetable = (pde_t*)kalloc()) == 0)
800013fc:	02060c63          	beqz	a2,80001434 <walk+0xc0>
80001400:	00000097          	auipc	ra,0x0
80001404:	8e0080e7          	jalr	-1824(ra) # 80000ce0 <kalloc>
80001408:	00050913          	mv	s2,a0
8000140c:	fc0500e3          	beqz	a0,800013cc <walk+0x58>
      memset(pagetable, 0, PGSIZE);
80001410:	00001637          	lui	a2,0x1
80001414:	00000593          	li	a1,0
80001418:	00000097          	auipc	ra,0x0
8000141c:	bb8080e7          	jalr	-1096(ra) # 80000fd0 <memset>
      *pte = PA2PTE(pagetable) | PTE_V;
80001420:	00c95793          	srli	a5,s2,0xc
80001424:	00a79793          	slli	a5,a5,0xa
80001428:	0017e793          	ori	a5,a5,1
8000142c:	00f9a023          	sw	a5,0(s3)
80001430:	f8dff06f          	j	800013bc <walk+0x48>
        return 0;
80001434:	00000913          	li	s2,0
80001438:	f95ff06f          	j	800013cc <walk+0x58>

8000143c <freewalk>:

// Recursively free page-table pages.
// All leaf mappings must already have been removed.
static void
freewalk(pagetable_t pagetable)
{
8000143c:	fe010113          	addi	sp,sp,-32
80001440:	00112e23          	sw	ra,28(sp)
80001444:	00812c23          	sw	s0,24(sp)
80001448:	00912a23          	sw	s1,20(sp)
8000144c:	01212823          	sw	s2,16(sp)
80001450:	01312623          	sw	s3,12(sp)
80001454:	02010413          	addi	s0,sp,32
80001458:	00050993          	mv	s3,a0
  // there are 2^9 = 512 PTEs in a page table.
  for(int i = 0; i < 512; i++){
8000145c:	00050493          	mv	s1,a0
80001460:	7ff50913          	addi	s2,a0,2047
80001464:	00190913          	addi	s2,s2,1
80001468:	01c0006f          	j	80001484 <freewalk+0x48>
      // this PTE points to a lower-level page table.
      uint32 child = PTE2PA(pte);
      freewalk((pagetable_t)child);
      pagetable[i] = 0;
    } else if(pte & PTE_V){
      panic("freewalk: leaf");
8000146c:	00008517          	auipc	a0,0x8
80001470:	d6450513          	addi	a0,a0,-668 # 800091d0 <userret+0x130>
80001474:	fffff097          	auipc	ra,0xfffff
80001478:	288080e7          	jalr	648(ra) # 800006fc <panic>
  for(int i = 0; i < 512; i++){
8000147c:	00448493          	addi	s1,s1,4
80001480:	03248863          	beq	s1,s2,800014b0 <freewalk+0x74>
    pte_t pte = pagetable[i];
80001484:	0004a783          	lw	a5,0(s1)
    if((pte & PTE_V) && (pte & (PTE_R|PTE_W|PTE_X)) == 0){
80001488:	0017f713          	andi	a4,a5,1
8000148c:	fe0708e3          	beqz	a4,8000147c <freewalk+0x40>
80001490:	00e7f713          	andi	a4,a5,14
80001494:	fc071ce3          	bnez	a4,8000146c <freewalk+0x30>
      uint32 child = PTE2PA(pte);
80001498:	00a7d793          	srli	a5,a5,0xa
      freewalk((pagetable_t)child);
8000149c:	00c79513          	slli	a0,a5,0xc
800014a0:	00000097          	auipc	ra,0x0
800014a4:	f9c080e7          	jalr	-100(ra) # 8000143c <freewalk>
      pagetable[i] = 0;
800014a8:	0004a023          	sw	zero,0(s1)
    if((pte & PTE_V) && (pte & (PTE_R|PTE_W|PTE_X)) == 0){
800014ac:	fd1ff06f          	j	8000147c <freewalk+0x40>
    }
  }
  kfree((void*)pagetable);
800014b0:	00098513          	mv	a0,s3
800014b4:	fffff097          	auipc	ra,0xfffff
800014b8:	6bc080e7          	jalr	1724(ra) # 80000b70 <kfree>
}
800014bc:	01c12083          	lw	ra,28(sp)
800014c0:	01812403          	lw	s0,24(sp)
800014c4:	01412483          	lw	s1,20(sp)
800014c8:	01012903          	lw	s2,16(sp)
800014cc:	00c12983          	lw	s3,12(sp)
800014d0:	02010113          	addi	sp,sp,32
800014d4:	00008067          	ret

800014d8 <kvminithart>:
{
800014d8:	ff010113          	addi	sp,sp,-16
800014dc:	00112623          	sw	ra,12(sp)
800014e0:	00812423          	sw	s0,8(sp)
800014e4:	01010413          	addi	s0,sp,16
  w_satp(MAKE_SATP(kernel_pagetable));
800014e8:	00023797          	auipc	a5,0x23
800014ec:	b207a783          	lw	a5,-1248(a5) # 80024008 <kernel_pagetable>
800014f0:	00c7d793          	srli	a5,a5,0xc
800014f4:	80000737          	lui	a4,0x80000
800014f8:	00e7e7b3          	or	a5,a5,a4
  asm volatile("csrw satp, %0" : : "r" (x));
800014fc:	18079073          	csrw	satp,a5
// flush the TLB.
static inline void
sfence_vma()
{
  // the zero, zero means flush all TLB entries.
  asm volatile("sfence.vma zero, zero");
80001500:	12000073          	sfence.vma
}
80001504:	00c12083          	lw	ra,12(sp)
80001508:	00812403          	lw	s0,8(sp)
8000150c:	01010113          	addi	sp,sp,16
80001510:	00008067          	ret

80001514 <walkaddr>:
  if(va >= MAXVA)
80001514:	fff00793          	li	a5,-1
80001518:	04f58a63          	beq	a1,a5,8000156c <walkaddr+0x58>
{
8000151c:	ff010113          	addi	sp,sp,-16
80001520:	00112623          	sw	ra,12(sp)
80001524:	00812423          	sw	s0,8(sp)
80001528:	01010413          	addi	s0,sp,16
  pte = walk(pagetable, va, 0);
8000152c:	00000613          	li	a2,0
80001530:	00000097          	auipc	ra,0x0
80001534:	e44080e7          	jalr	-444(ra) # 80001374 <walk>
  if(pte == 0)
80001538:	00050c63          	beqz	a0,80001550 <walkaddr+0x3c>
  if((*pte & PTE_V) == 0)
8000153c:	00052783          	lw	a5,0(a0)
  if((*pte & PTE_U) == 0)
80001540:	0117f693          	andi	a3,a5,17
80001544:	01100713          	li	a4,17
    return 0;
80001548:	00000513          	li	a0,0
  if((*pte & PTE_U) == 0)
8000154c:	00e68a63          	beq	a3,a4,80001560 <walkaddr+0x4c>
}
80001550:	00c12083          	lw	ra,12(sp)
80001554:	00812403          	lw	s0,8(sp)
80001558:	01010113          	addi	sp,sp,16
8000155c:	00008067          	ret
  pa = PTE2PA(*pte);
80001560:	00a7d793          	srli	a5,a5,0xa
80001564:	00c79513          	slli	a0,a5,0xc
  return pa;
80001568:	fe9ff06f          	j	80001550 <walkaddr+0x3c>
    return 0;
8000156c:	00000513          	li	a0,0
}
80001570:	00008067          	ret

80001574 <kvmpa>:
{
80001574:	ff010113          	addi	sp,sp,-16
80001578:	00112623          	sw	ra,12(sp)
8000157c:	00812423          	sw	s0,8(sp)
80001580:	00912223          	sw	s1,4(sp)
80001584:	01010413          	addi	s0,sp,16
80001588:	00050493          	mv	s1,a0
  pte = walk(kernel_pagetable, va, 0);
8000158c:	00000613          	li	a2,0
80001590:	00050593          	mv	a1,a0
80001594:	00023517          	auipc	a0,0x23
80001598:	a7452503          	lw	a0,-1420(a0) # 80024008 <kernel_pagetable>
8000159c:	00000097          	auipc	ra,0x0
800015a0:	dd8080e7          	jalr	-552(ra) # 80001374 <walk>
  if(pte == 0)
800015a4:	02050c63          	beqz	a0,800015dc <kvmpa+0x68>
  if((*pte & PTE_V) == 0)
800015a8:	00052503          	lw	a0,0(a0)
800015ac:	00157793          	andi	a5,a0,1
800015b0:	02078e63          	beqz	a5,800015ec <kvmpa+0x78>
  pa = PTE2PA(*pte);
800015b4:	00a55513          	srli	a0,a0,0xa
800015b8:	00c51513          	slli	a0,a0,0xc
  uint32 off = va % PGSIZE;
800015bc:	01449493          	slli	s1,s1,0x14
800015c0:	0144d493          	srli	s1,s1,0x14
}
800015c4:	00950533          	add	a0,a0,s1
800015c8:	00c12083          	lw	ra,12(sp)
800015cc:	00812403          	lw	s0,8(sp)
800015d0:	00412483          	lw	s1,4(sp)
800015d4:	01010113          	addi	sp,sp,16
800015d8:	00008067          	ret
    panic("kvmpa");
800015dc:	00008517          	auipc	a0,0x8
800015e0:	c0450513          	addi	a0,a0,-1020 # 800091e0 <userret+0x140>
800015e4:	fffff097          	auipc	ra,0xfffff
800015e8:	118080e7          	jalr	280(ra) # 800006fc <panic>
    panic("kvmpa");
800015ec:	00008517          	auipc	a0,0x8
800015f0:	bf450513          	addi	a0,a0,-1036 # 800091e0 <userret+0x140>
800015f4:	fffff097          	auipc	ra,0xfffff
800015f8:	108080e7          	jalr	264(ra) # 800006fc <panic>

800015fc <mappages>:
{
800015fc:	fd010113          	addi	sp,sp,-48
80001600:	02112623          	sw	ra,44(sp)
80001604:	02812423          	sw	s0,40(sp)
80001608:	02912223          	sw	s1,36(sp)
8000160c:	03212023          	sw	s2,32(sp)
80001610:	01312e23          	sw	s3,28(sp)
80001614:	01412c23          	sw	s4,24(sp)
80001618:	01512a23          	sw	s5,20(sp)
8000161c:	01612823          	sw	s6,16(sp)
80001620:	01712623          	sw	s7,12(sp)
80001624:	03010413          	addi	s0,sp,48
80001628:	00050993          	mv	s3,a0
8000162c:	00070a93          	mv	s5,a4
  a = PGROUNDDOWN(va);
80001630:	fffff737          	lui	a4,0xfffff
80001634:	00e5f7b3          	and	a5,a1,a4
  last = PGROUNDDOWN(va + size - 1);
80001638:	fff60913          	addi	s2,a2,-1 # fff <_entry-0x7ffff001>
8000163c:	00b90933          	add	s2,s2,a1
80001640:	00e97933          	and	s2,s2,a4
  a = PGROUNDDOWN(va);
80001644:	00078493          	mv	s1,a5
    if((pte = walk(pagetable, a, 1)) == 0)
80001648:	00100b13          	li	s6,1
8000164c:	40f68a33          	sub	s4,a3,a5
    a += PGSIZE;
80001650:	00001bb7          	lui	s7,0x1
    if((pte = walk(pagetable, a, 1)) == 0)
80001654:	000b0613          	mv	a2,s6
80001658:	00048593          	mv	a1,s1
8000165c:	00098513          	mv	a0,s3
80001660:	00000097          	auipc	ra,0x0
80001664:	d14080e7          	jalr	-748(ra) # 80001374 <walk>
80001668:	04050263          	beqz	a0,800016ac <mappages+0xb0>
    if(*pte & PTE_V)
8000166c:	00052783          	lw	a5,0(a0)
80001670:	0017f793          	andi	a5,a5,1
80001674:	02079463          	bnez	a5,8000169c <mappages+0xa0>
    *pte = PA2PTE(pa) | perm | PTE_V;
80001678:	014487b3          	add	a5,s1,s4
8000167c:	00c7d793          	srli	a5,a5,0xc
80001680:	00a79793          	slli	a5,a5,0xa
80001684:	0157e7b3          	or	a5,a5,s5
80001688:	0017e793          	ori	a5,a5,1
8000168c:	00f52023          	sw	a5,0(a0)
    if(a == last)
80001690:	05248663          	beq	s1,s2,800016dc <mappages+0xe0>
    a += PGSIZE;
80001694:	017484b3          	add	s1,s1,s7
    if((pte = walk(pagetable, a, 1)) == 0)
80001698:	fbdff06f          	j	80001654 <mappages+0x58>
      panic("remap");
8000169c:	00008517          	auipc	a0,0x8
800016a0:	b4c50513          	addi	a0,a0,-1204 # 800091e8 <userret+0x148>
800016a4:	fffff097          	auipc	ra,0xfffff
800016a8:	058080e7          	jalr	88(ra) # 800006fc <panic>
      return -1;
800016ac:	fff00513          	li	a0,-1
}
800016b0:	02c12083          	lw	ra,44(sp)
800016b4:	02812403          	lw	s0,40(sp)
800016b8:	02412483          	lw	s1,36(sp)
800016bc:	02012903          	lw	s2,32(sp)
800016c0:	01c12983          	lw	s3,28(sp)
800016c4:	01812a03          	lw	s4,24(sp)
800016c8:	01412a83          	lw	s5,20(sp)
800016cc:	01012b03          	lw	s6,16(sp)
800016d0:	00c12b83          	lw	s7,12(sp)
800016d4:	03010113          	addi	sp,sp,48
800016d8:	00008067          	ret
  return 0;
800016dc:	00000513          	li	a0,0
800016e0:	fd1ff06f          	j	800016b0 <mappages+0xb4>

800016e4 <kvmmap>:
{
800016e4:	ff010113          	addi	sp,sp,-16
800016e8:	00112623          	sw	ra,12(sp)
800016ec:	00812423          	sw	s0,8(sp)
800016f0:	01010413          	addi	s0,sp,16
800016f4:	00068713          	mv	a4,a3
  if(mappages(kernel_pagetable, va, sz, pa, perm) != 0)
800016f8:	00058693          	mv	a3,a1
800016fc:	00050593          	mv	a1,a0
80001700:	00023517          	auipc	a0,0x23
80001704:	90852503          	lw	a0,-1784(a0) # 80024008 <kernel_pagetable>
80001708:	00000097          	auipc	ra,0x0
8000170c:	ef4080e7          	jalr	-268(ra) # 800015fc <mappages>
80001710:	00051a63          	bnez	a0,80001724 <kvmmap+0x40>
}
80001714:	00c12083          	lw	ra,12(sp)
80001718:	00812403          	lw	s0,8(sp)
8000171c:	01010113          	addi	sp,sp,16
80001720:	00008067          	ret
    panic("kvmmap");
80001724:	00008517          	auipc	a0,0x8
80001728:	acc50513          	addi	a0,a0,-1332 # 800091f0 <userret+0x150>
8000172c:	fffff097          	auipc	ra,0xfffff
80001730:	fd0080e7          	jalr	-48(ra) # 800006fc <panic>

80001734 <kvminit>:
{
80001734:	ff010113          	addi	sp,sp,-16
80001738:	00112623          	sw	ra,12(sp)
8000173c:	00812423          	sw	s0,8(sp)
80001740:	01010413          	addi	s0,sp,16
  kernel_pagetable = (pagetable_t) kalloc();
80001744:	fffff097          	auipc	ra,0xfffff
80001748:	59c080e7          	jalr	1436(ra) # 80000ce0 <kalloc>
8000174c:	00023797          	auipc	a5,0x23
80001750:	8aa7ae23          	sw	a0,-1860(a5) # 80024008 <kernel_pagetable>
  if (kernel_pagetable == 0) { 
80001754:	0e050463          	beqz	a0,8000183c <kvminit+0x108>
  memset(kernel_pagetable, 0, PGSIZE);
80001758:	00001637          	lui	a2,0x1
8000175c:	00000593          	li	a1,0
80001760:	00023517          	auipc	a0,0x23
80001764:	8a852503          	lw	a0,-1880(a0) # 80024008 <kernel_pagetable>
80001768:	00000097          	auipc	ra,0x0
8000176c:	868080e7          	jalr	-1944(ra) # 80000fd0 <memset>
  kvmmap(UART0, UART0, PGSIZE, PTE_R | PTE_W);
80001770:	00600693          	li	a3,6
80001774:	00001637          	lui	a2,0x1
80001778:	100005b7          	lui	a1,0x10000
8000177c:	00058513          	mv	a0,a1
80001780:	00000097          	auipc	ra,0x0
80001784:	f64080e7          	jalr	-156(ra) # 800016e4 <kvmmap>
  kvmmap(VIRTIO0, VIRTIO0, PGSIZE, PTE_R | PTE_W);
80001788:	00600693          	li	a3,6
8000178c:	00001637          	lui	a2,0x1
80001790:	100015b7          	lui	a1,0x10001
80001794:	00058513          	mv	a0,a1
80001798:	00000097          	auipc	ra,0x0
8000179c:	f4c080e7          	jalr	-180(ra) # 800016e4 <kvmmap>
  kvmmap(CLINT, CLINT, 0x10000, PTE_R | PTE_W);
800017a0:	00600693          	li	a3,6
800017a4:	00010637          	lui	a2,0x10
800017a8:	020005b7          	lui	a1,0x2000
800017ac:	00058513          	mv	a0,a1
800017b0:	00000097          	auipc	ra,0x0
800017b4:	f34080e7          	jalr	-204(ra) # 800016e4 <kvmmap>
  kvmmap(PLIC, PLIC, 0x400000, PTE_R | PTE_W);
800017b8:	00600693          	li	a3,6
800017bc:	00400637          	lui	a2,0x400
800017c0:	0c0005b7          	lui	a1,0xc000
800017c4:	00058513          	mv	a0,a1
800017c8:	00000097          	auipc	ra,0x0
800017cc:	f1c080e7          	jalr	-228(ra) # 800016e4 <kvmmap>
  kvmmap(KERNBASE, KERNBASE, (uint32)etext-KERNBASE, PTE_R | PTE_X);
800017d0:	00a00693          	li	a3,10
800017d4:	80009617          	auipc	a2,0x80009
800017d8:	82c60613          	addi	a2,a2,-2004 # a000 <_entry-0x7fff6000>
800017dc:	800005b7          	lui	a1,0x80000
800017e0:	00058513          	mv	a0,a1
800017e4:	00000097          	auipc	ra,0x0
800017e8:	f00080e7          	jalr	-256(ra) # 800016e4 <kvmmap>
  kvmmap((uint32)etext, (uint32)etext, PHYSTOP-(uint32)etext, PTE_R | PTE_W);
800017ec:	00600693          	li	a3,6
800017f0:	00009797          	auipc	a5,0x9
800017f4:	81078793          	addi	a5,a5,-2032 # 8000a000 <initcode>
800017f8:	88000637          	lui	a2,0x88000
800017fc:	40f60633          	sub	a2,a2,a5
80001800:	00078593          	mv	a1,a5
80001804:	00078513          	mv	a0,a5
80001808:	00000097          	auipc	ra,0x0
8000180c:	edc080e7          	jalr	-292(ra) # 800016e4 <kvmmap>
  kvmmap(TRAMPOLINE, (uint32)trampoline, PGSIZE, PTE_R | PTE_X);
80001810:	00a00693          	li	a3,10
80001814:	00001637          	lui	a2,0x1
80001818:	00007597          	auipc	a1,0x7
8000181c:	7e858593          	addi	a1,a1,2024 # 80009000 <trampoline>
80001820:	fffff537          	lui	a0,0xfffff
80001824:	00000097          	auipc	ra,0x0
80001828:	ec0080e7          	jalr	-320(ra) # 800016e4 <kvmmap>
}
8000182c:	00c12083          	lw	ra,12(sp)
80001830:	00812403          	lw	s0,8(sp)
80001834:	01010113          	addi	sp,sp,16
80001838:	00008067          	ret
    printf("kalloc failed\n");
8000183c:	00008517          	auipc	a0,0x8
80001840:	9bc50513          	addi	a0,a0,-1604 # 800091f8 <userret+0x158>
80001844:	fffff097          	auipc	ra,0xfffff
80001848:	f14080e7          	jalr	-236(ra) # 80000758 <printf>
8000184c:	f0dff06f          	j	80001758 <kvminit+0x24>

80001850 <uvmunmap>:
{
80001850:	fd010113          	addi	sp,sp,-48
80001854:	02112623          	sw	ra,44(sp)
80001858:	02812423          	sw	s0,40(sp)
8000185c:	02912223          	sw	s1,36(sp)
80001860:	03212023          	sw	s2,32(sp)
80001864:	01312e23          	sw	s3,28(sp)
80001868:	01412c23          	sw	s4,24(sp)
8000186c:	01512a23          	sw	s5,20(sp)
80001870:	01612823          	sw	s6,16(sp)
80001874:	01712623          	sw	s7,12(sp)
80001878:	03010413          	addi	s0,sp,48
8000187c:	00050a13          	mv	s4,a0
80001880:	00068a93          	mv	s5,a3
  a = PGROUNDDOWN(va);
80001884:	fffff7b7          	lui	a5,0xfffff
80001888:	00f5f933          	and	s2,a1,a5
  last = PGROUNDDOWN(va + size - 1);
8000188c:	fff60993          	addi	s3,a2,-1 # fff <_entry-0x7ffff001>
80001890:	00b989b3          	add	s3,s3,a1
80001894:	00f9f9b3          	and	s3,s3,a5
    if(PTE_FLAGS(*pte) == PTE_V)
80001898:	00100b13          	li	s6,1
    a += PGSIZE;
8000189c:	00001bb7          	lui	s7,0x1
800018a0:	0540006f          	j	800018f4 <uvmunmap+0xa4>
      panic("uvmunmap: walk");
800018a4:	00008517          	auipc	a0,0x8
800018a8:	96450513          	addi	a0,a0,-1692 # 80009208 <userret+0x168>
800018ac:	fffff097          	auipc	ra,0xfffff
800018b0:	e50080e7          	jalr	-432(ra) # 800006fc <panic>
      printf("va=%p pte=%p\n", a, *pte);
800018b4:	00090593          	mv	a1,s2
800018b8:	00008517          	auipc	a0,0x8
800018bc:	96050513          	addi	a0,a0,-1696 # 80009218 <userret+0x178>
800018c0:	fffff097          	auipc	ra,0xfffff
800018c4:	e98080e7          	jalr	-360(ra) # 80000758 <printf>
      panic("uvmunmap: not mapped");
800018c8:	00008517          	auipc	a0,0x8
800018cc:	96050513          	addi	a0,a0,-1696 # 80009228 <userret+0x188>
800018d0:	fffff097          	auipc	ra,0xfffff
800018d4:	e2c080e7          	jalr	-468(ra) # 800006fc <panic>
      panic("uvmunmap: not a leaf");
800018d8:	00008517          	auipc	a0,0x8
800018dc:	96850513          	addi	a0,a0,-1688 # 80009240 <userret+0x1a0>
800018e0:	fffff097          	auipc	ra,0xfffff
800018e4:	e1c080e7          	jalr	-484(ra) # 800006fc <panic>
    *pte = 0;
800018e8:	0004a023          	sw	zero,0(s1)
    if(a == last)
800018ec:	05390863          	beq	s2,s3,8000193c <uvmunmap+0xec>
    a += PGSIZE;
800018f0:	01790933          	add	s2,s2,s7
    if((pte = walk(pagetable, a, 0)) == 0)
800018f4:	00000613          	li	a2,0
800018f8:	00090593          	mv	a1,s2
800018fc:	000a0513          	mv	a0,s4
80001900:	00000097          	auipc	ra,0x0
80001904:	a74080e7          	jalr	-1420(ra) # 80001374 <walk>
80001908:	00050493          	mv	s1,a0
8000190c:	f8050ce3          	beqz	a0,800018a4 <uvmunmap+0x54>
    if((*pte & PTE_V) == 0){
80001910:	00052603          	lw	a2,0(a0)
80001914:	00167793          	andi	a5,a2,1
80001918:	f8078ee3          	beqz	a5,800018b4 <uvmunmap+0x64>
    if(PTE_FLAGS(*pte) == PTE_V)
8000191c:	3ff67793          	andi	a5,a2,1023
80001920:	fb678ce3          	beq	a5,s6,800018d8 <uvmunmap+0x88>
    if(do_free){
80001924:	fc0a82e3          	beqz	s5,800018e8 <uvmunmap+0x98>
      pa = PTE2PA(*pte);
80001928:	00a65613          	srli	a2,a2,0xa
      kfree((void*)pa);
8000192c:	00c61513          	slli	a0,a2,0xc
80001930:	fffff097          	auipc	ra,0xfffff
80001934:	240080e7          	jalr	576(ra) # 80000b70 <kfree>
80001938:	fb1ff06f          	j	800018e8 <uvmunmap+0x98>
}
8000193c:	02c12083          	lw	ra,44(sp)
80001940:	02812403          	lw	s0,40(sp)
80001944:	02412483          	lw	s1,36(sp)
80001948:	02012903          	lw	s2,32(sp)
8000194c:	01c12983          	lw	s3,28(sp)
80001950:	01812a03          	lw	s4,24(sp)
80001954:	01412a83          	lw	s5,20(sp)
80001958:	01012b03          	lw	s6,16(sp)
8000195c:	00c12b83          	lw	s7,12(sp)
80001960:	03010113          	addi	sp,sp,48
80001964:	00008067          	ret

80001968 <uvmcreate>:
{
80001968:	ff010113          	addi	sp,sp,-16
8000196c:	00112623          	sw	ra,12(sp)
80001970:	00812423          	sw	s0,8(sp)
80001974:	00912223          	sw	s1,4(sp)
80001978:	01010413          	addi	s0,sp,16
  pagetable = (pagetable_t) kalloc();
8000197c:	fffff097          	auipc	ra,0xfffff
80001980:	364080e7          	jalr	868(ra) # 80000ce0 <kalloc>
  if(pagetable == 0)
80001984:	02050863          	beqz	a0,800019b4 <uvmcreate+0x4c>
80001988:	00050493          	mv	s1,a0
  memset(pagetable, 0, PGSIZE);
8000198c:	00001637          	lui	a2,0x1
80001990:	00000593          	li	a1,0
80001994:	fffff097          	auipc	ra,0xfffff
80001998:	63c080e7          	jalr	1596(ra) # 80000fd0 <memset>
}
8000199c:	00048513          	mv	a0,s1
800019a0:	00c12083          	lw	ra,12(sp)
800019a4:	00812403          	lw	s0,8(sp)
800019a8:	00412483          	lw	s1,4(sp)
800019ac:	01010113          	addi	sp,sp,16
800019b0:	00008067          	ret
    panic("uvmcreate: out of memory");
800019b4:	00008517          	auipc	a0,0x8
800019b8:	8a450513          	addi	a0,a0,-1884 # 80009258 <userret+0x1b8>
800019bc:	fffff097          	auipc	ra,0xfffff
800019c0:	d40080e7          	jalr	-704(ra) # 800006fc <panic>

800019c4 <uvminit>:
{
800019c4:	fe010113          	addi	sp,sp,-32
800019c8:	00112e23          	sw	ra,28(sp)
800019cc:	00812c23          	sw	s0,24(sp)
800019d0:	00912a23          	sw	s1,20(sp)
800019d4:	01212823          	sw	s2,16(sp)
800019d8:	01312623          	sw	s3,12(sp)
800019dc:	01412423          	sw	s4,8(sp)
800019e0:	02010413          	addi	s0,sp,32
  if(sz >= PGSIZE)
800019e4:	000017b7          	lui	a5,0x1
800019e8:	06f67e63          	bgeu	a2,a5,80001a64 <uvminit+0xa0>
800019ec:	00050993          	mv	s3,a0
800019f0:	00058a13          	mv	s4,a1
800019f4:	00060493          	mv	s1,a2
  mem = kalloc();
800019f8:	fffff097          	auipc	ra,0xfffff
800019fc:	2e8080e7          	jalr	744(ra) # 80000ce0 <kalloc>
80001a00:	00050913          	mv	s2,a0
  memset(mem, 0, PGSIZE);
80001a04:	00001637          	lui	a2,0x1
80001a08:	00000593          	li	a1,0
80001a0c:	fffff097          	auipc	ra,0xfffff
80001a10:	5c4080e7          	jalr	1476(ra) # 80000fd0 <memset>
  mappages(pagetable, 0, PGSIZE, (uint32)mem, PTE_W|PTE_R|PTE_X|PTE_U);
80001a14:	01e00713          	li	a4,30
80001a18:	00090693          	mv	a3,s2
80001a1c:	00001637          	lui	a2,0x1
80001a20:	00000593          	li	a1,0
80001a24:	00098513          	mv	a0,s3
80001a28:	00000097          	auipc	ra,0x0
80001a2c:	bd4080e7          	jalr	-1068(ra) # 800015fc <mappages>
  memmove(mem, src, sz);
80001a30:	00048613          	mv	a2,s1
80001a34:	000a0593          	mv	a1,s4
80001a38:	00090513          	mv	a0,s2
80001a3c:	fffff097          	auipc	ra,0xfffff
80001a40:	620080e7          	jalr	1568(ra) # 8000105c <memmove>
}
80001a44:	01c12083          	lw	ra,28(sp)
80001a48:	01812403          	lw	s0,24(sp)
80001a4c:	01412483          	lw	s1,20(sp)
80001a50:	01012903          	lw	s2,16(sp)
80001a54:	00c12983          	lw	s3,12(sp)
80001a58:	00812a03          	lw	s4,8(sp)
80001a5c:	02010113          	addi	sp,sp,32
80001a60:	00008067          	ret
    panic("inituvm: more than a page");
80001a64:	00008517          	auipc	a0,0x8
80001a68:	81050513          	addi	a0,a0,-2032 # 80009274 <userret+0x1d4>
80001a6c:	fffff097          	auipc	ra,0xfffff
80001a70:	c90080e7          	jalr	-880(ra) # 800006fc <panic>

80001a74 <uvmdealloc>:
{
80001a74:	ff010113          	addi	sp,sp,-16
80001a78:	00112623          	sw	ra,12(sp)
80001a7c:	00812423          	sw	s0,8(sp)
80001a80:	00912223          	sw	s1,4(sp)
80001a84:	01010413          	addi	s0,sp,16
    return oldsz;
80001a88:	00058493          	mv	s1,a1
  if(newsz >= oldsz)
80001a8c:	02b67463          	bgeu	a2,a1,80001ab4 <uvmdealloc+0x40>
80001a90:	00060493          	mv	s1,a2
  uint32 newup = PGROUNDUP(newsz);
80001a94:	000017b7          	lui	a5,0x1
80001a98:	fff78793          	addi	a5,a5,-1 # fff <_entry-0x7ffff001>
80001a9c:	00f60733          	add	a4,a2,a5
80001aa0:	fffff6b7          	lui	a3,0xfffff
80001aa4:	00d77733          	and	a4,a4,a3
  if(newup < PGROUNDUP(oldsz))
80001aa8:	00f587b3          	add	a5,a1,a5
80001aac:	00d7f7b3          	and	a5,a5,a3
80001ab0:	00f76e63          	bltu	a4,a5,80001acc <uvmdealloc+0x58>
}
80001ab4:	00048513          	mv	a0,s1
80001ab8:	00c12083          	lw	ra,12(sp)
80001abc:	00812403          	lw	s0,8(sp)
80001ac0:	00412483          	lw	s1,4(sp)
80001ac4:	01010113          	addi	sp,sp,16
80001ac8:	00008067          	ret
    uvmunmap(pagetable, newup, oldsz - newup, 1);
80001acc:	00100693          	li	a3,1
80001ad0:	40e58633          	sub	a2,a1,a4
80001ad4:	00070593          	mv	a1,a4
80001ad8:	00000097          	auipc	ra,0x0
80001adc:	d78080e7          	jalr	-648(ra) # 80001850 <uvmunmap>
80001ae0:	fd5ff06f          	j	80001ab4 <uvmdealloc+0x40>

80001ae4 <uvmalloc>:
  if(newsz < oldsz)
80001ae4:	12b66e63          	bltu	a2,a1,80001c20 <uvmalloc+0x13c>
{
80001ae8:	fd010113          	addi	sp,sp,-48
80001aec:	02112623          	sw	ra,44(sp)
80001af0:	02812423          	sw	s0,40(sp)
80001af4:	01412c23          	sw	s4,24(sp)
80001af8:	01512a23          	sw	s5,20(sp)
80001afc:	01712623          	sw	s7,12(sp)
80001b00:	03010413          	addi	s0,sp,48
80001b04:	00050a93          	mv	s5,a0
80001b08:	00060a13          	mv	s4,a2
  oldsz = PGROUNDUP(oldsz);
80001b0c:	000017b7          	lui	a5,0x1
80001b10:	fff78793          	addi	a5,a5,-1 # fff <_entry-0x7ffff001>
80001b14:	00f585b3          	add	a1,a1,a5
80001b18:	fffff7b7          	lui	a5,0xfffff
80001b1c:	00f5f7b3          	and	a5,a1,a5
80001b20:	00078b93          	mv	s7,a5
  for(; a < newsz; a += PGSIZE){
80001b24:	10c7f263          	bgeu	a5,a2,80001c28 <uvmalloc+0x144>
80001b28:	02912223          	sw	s1,36(sp)
80001b2c:	03212023          	sw	s2,32(sp)
80001b30:	01312e23          	sw	s3,28(sp)
80001b34:	01612823          	sw	s6,16(sp)
  a = oldsz;
80001b38:	00078913          	mv	s2,a5
    memset(mem, 0, PGSIZE);
80001b3c:	000019b7          	lui	s3,0x1
    if(mappages(pagetable, a, PGSIZE, (uint32)mem, PTE_W|PTE_X|PTE_R|PTE_U) != 0){
80001b40:	01e00b13          	li	s6,30
    mem = kalloc();
80001b44:	fffff097          	auipc	ra,0xfffff
80001b48:	19c080e7          	jalr	412(ra) # 80000ce0 <kalloc>
80001b4c:	00050493          	mv	s1,a0
    if(mem == 0){
80001b50:	04050a63          	beqz	a0,80001ba4 <uvmalloc+0xc0>
    memset(mem, 0, PGSIZE);
80001b54:	00098613          	mv	a2,s3
80001b58:	00000593          	li	a1,0
80001b5c:	fffff097          	auipc	ra,0xfffff
80001b60:	474080e7          	jalr	1140(ra) # 80000fd0 <memset>
    if(mappages(pagetable, a, PGSIZE, (uint32)mem, PTE_W|PTE_X|PTE_R|PTE_U) != 0){
80001b64:	000b0713          	mv	a4,s6
80001b68:	00048693          	mv	a3,s1
80001b6c:	00098613          	mv	a2,s3
80001b70:	00090593          	mv	a1,s2
80001b74:	000a8513          	mv	a0,s5
80001b78:	00000097          	auipc	ra,0x0
80001b7c:	a84080e7          	jalr	-1404(ra) # 800015fc <mappages>
80001b80:	06051463          	bnez	a0,80001be8 <uvmalloc+0x104>
  for(; a < newsz; a += PGSIZE){
80001b84:	01390933          	add	s2,s2,s3
80001b88:	fb496ee3          	bltu	s2,s4,80001b44 <uvmalloc+0x60>
  return newsz;
80001b8c:	000a0513          	mv	a0,s4
80001b90:	02412483          	lw	s1,36(sp)
80001b94:	02012903          	lw	s2,32(sp)
80001b98:	01c12983          	lw	s3,28(sp)
80001b9c:	01012b03          	lw	s6,16(sp)
80001ba0:	02c0006f          	j	80001bcc <uvmalloc+0xe8>
      uvmdealloc(pagetable, a, oldsz);
80001ba4:	000b8613          	mv	a2,s7
80001ba8:	00090593          	mv	a1,s2
80001bac:	000a8513          	mv	a0,s5
80001bb0:	00000097          	auipc	ra,0x0
80001bb4:	ec4080e7          	jalr	-316(ra) # 80001a74 <uvmdealloc>
      return 0;
80001bb8:	00000513          	li	a0,0
80001bbc:	02412483          	lw	s1,36(sp)
80001bc0:	02012903          	lw	s2,32(sp)
80001bc4:	01c12983          	lw	s3,28(sp)
80001bc8:	01012b03          	lw	s6,16(sp)
}
80001bcc:	02c12083          	lw	ra,44(sp)
80001bd0:	02812403          	lw	s0,40(sp)
80001bd4:	01812a03          	lw	s4,24(sp)
80001bd8:	01412a83          	lw	s5,20(sp)
80001bdc:	00c12b83          	lw	s7,12(sp)
80001be0:	03010113          	addi	sp,sp,48
80001be4:	00008067          	ret
      kfree(mem);
80001be8:	00048513          	mv	a0,s1
80001bec:	fffff097          	auipc	ra,0xfffff
80001bf0:	f84080e7          	jalr	-124(ra) # 80000b70 <kfree>
      uvmdealloc(pagetable, a, oldsz);
80001bf4:	000b8613          	mv	a2,s7
80001bf8:	00090593          	mv	a1,s2
80001bfc:	000a8513          	mv	a0,s5
80001c00:	00000097          	auipc	ra,0x0
80001c04:	e74080e7          	jalr	-396(ra) # 80001a74 <uvmdealloc>
      return 0;
80001c08:	00000513          	li	a0,0
80001c0c:	02412483          	lw	s1,36(sp)
80001c10:	02012903          	lw	s2,32(sp)
80001c14:	01c12983          	lw	s3,28(sp)
80001c18:	01012b03          	lw	s6,16(sp)
80001c1c:	fb1ff06f          	j	80001bcc <uvmalloc+0xe8>
    return oldsz;
80001c20:	00058513          	mv	a0,a1
}
80001c24:	00008067          	ret
  return newsz;
80001c28:	00060513          	mv	a0,a2
80001c2c:	fa1ff06f          	j	80001bcc <uvmalloc+0xe8>

80001c30 <uvmfree>:

// Free user memory pages,
// then free page-table pages.
void
uvmfree(pagetable_t pagetable, uint32 sz)
{
80001c30:	ff010113          	addi	sp,sp,-16
80001c34:	00112623          	sw	ra,12(sp)
80001c38:	00812423          	sw	s0,8(sp)
80001c3c:	00912223          	sw	s1,4(sp)
80001c40:	01010413          	addi	s0,sp,16
80001c44:	00050493          	mv	s1,a0
80001c48:	00058613          	mv	a2,a1
  uvmunmap(pagetable, 0, sz, 1);
80001c4c:	00100693          	li	a3,1
80001c50:	00000593          	li	a1,0
80001c54:	00000097          	auipc	ra,0x0
80001c58:	bfc080e7          	jalr	-1028(ra) # 80001850 <uvmunmap>
  freewalk(pagetable);
80001c5c:	00048513          	mv	a0,s1
80001c60:	fffff097          	auipc	ra,0xfffff
80001c64:	7dc080e7          	jalr	2012(ra) # 8000143c <freewalk>
}
80001c68:	00c12083          	lw	ra,12(sp)
80001c6c:	00812403          	lw	s0,8(sp)
80001c70:	00412483          	lw	s1,4(sp)
80001c74:	01010113          	addi	sp,sp,16
80001c78:	00008067          	ret

80001c7c <uvmcopy>:
  pte_t *pte;
  uint32 pa, i;
  uint flags;
  char *mem;

  for(i = 0; i < sz; i += PGSIZE){
80001c7c:	12060663          	beqz	a2,80001da8 <uvmcopy+0x12c>
{
80001c80:	fd010113          	addi	sp,sp,-48
80001c84:	02112623          	sw	ra,44(sp)
80001c88:	02812423          	sw	s0,40(sp)
80001c8c:	02912223          	sw	s1,36(sp)
80001c90:	03212023          	sw	s2,32(sp)
80001c94:	01312e23          	sw	s3,28(sp)
80001c98:	01412c23          	sw	s4,24(sp)
80001c9c:	01512a23          	sw	s5,20(sp)
80001ca0:	01612823          	sw	s6,16(sp)
80001ca4:	01712623          	sw	s7,12(sp)
80001ca8:	03010413          	addi	s0,sp,48
80001cac:	00050b13          	mv	s6,a0
80001cb0:	00058a93          	mv	s5,a1
80001cb4:	00060a13          	mv	s4,a2
  for(i = 0; i < sz; i += PGSIZE){
80001cb8:	00000913          	li	s2,0
      panic("uvmcopy: page not present");
    pa = PTE2PA(*pte);
    flags = PTE_FLAGS(*pte);
    if((mem = kalloc()) == 0)
      goto err;
    memmove(mem, (char*)pa, PGSIZE);
80001cbc:	000019b7          	lui	s3,0x1
    if((pte = walk(old, i, 0)) == 0)
80001cc0:	00000613          	li	a2,0
80001cc4:	00090593          	mv	a1,s2
80001cc8:	000b0513          	mv	a0,s6
80001ccc:	fffff097          	auipc	ra,0xfffff
80001cd0:	6a8080e7          	jalr	1704(ra) # 80001374 <walk>
80001cd4:	06050063          	beqz	a0,80001d34 <uvmcopy+0xb8>
    if((*pte & PTE_V) == 0)
80001cd8:	00052b83          	lw	s7,0(a0)
80001cdc:	001bf793          	andi	a5,s7,1
80001ce0:	06078263          	beqz	a5,80001d44 <uvmcopy+0xc8>
    if((mem = kalloc()) == 0)
80001ce4:	fffff097          	auipc	ra,0xfffff
80001ce8:	ffc080e7          	jalr	-4(ra) # 80000ce0 <kalloc>
80001cec:	00050493          	mv	s1,a0
80001cf0:	06050863          	beqz	a0,80001d60 <uvmcopy+0xe4>
    pa = PTE2PA(*pte);
80001cf4:	00abd593          	srli	a1,s7,0xa
    memmove(mem, (char*)pa, PGSIZE);
80001cf8:	00098613          	mv	a2,s3
80001cfc:	00c59593          	slli	a1,a1,0xc
80001d00:	fffff097          	auipc	ra,0xfffff
80001d04:	35c080e7          	jalr	860(ra) # 8000105c <memmove>
    if(mappages(new, i, PGSIZE, (uint32)mem, flags) != 0){
80001d08:	3ffbf713          	andi	a4,s7,1023
80001d0c:	00048693          	mv	a3,s1
80001d10:	00098613          	mv	a2,s3
80001d14:	00090593          	mv	a1,s2
80001d18:	000a8513          	mv	a0,s5
80001d1c:	00000097          	auipc	ra,0x0
80001d20:	8e0080e7          	jalr	-1824(ra) # 800015fc <mappages>
80001d24:	02051863          	bnez	a0,80001d54 <uvmcopy+0xd8>
  for(i = 0; i < sz; i += PGSIZE){
80001d28:	01390933          	add	s2,s2,s3
80001d2c:	f9496ae3          	bltu	s2,s4,80001cc0 <uvmcopy+0x44>
80001d30:	04c0006f          	j	80001d7c <uvmcopy+0x100>
      panic("uvmcopy: pte should exist");
80001d34:	00007517          	auipc	a0,0x7
80001d38:	55c50513          	addi	a0,a0,1372 # 80009290 <userret+0x1f0>
80001d3c:	fffff097          	auipc	ra,0xfffff
80001d40:	9c0080e7          	jalr	-1600(ra) # 800006fc <panic>
      panic("uvmcopy: page not present");
80001d44:	00007517          	auipc	a0,0x7
80001d48:	56850513          	addi	a0,a0,1384 # 800092ac <userret+0x20c>
80001d4c:	fffff097          	auipc	ra,0xfffff
80001d50:	9b0080e7          	jalr	-1616(ra) # 800006fc <panic>
      kfree(mem);
80001d54:	00048513          	mv	a0,s1
80001d58:	fffff097          	auipc	ra,0xfffff
80001d5c:	e18080e7          	jalr	-488(ra) # 80000b70 <kfree>
    }
  }
  return 0;

 err:
  uvmunmap(new, 0, i, 1);
80001d60:	00100693          	li	a3,1
80001d64:	00090613          	mv	a2,s2
80001d68:	00000593          	li	a1,0
80001d6c:	000a8513          	mv	a0,s5
80001d70:	00000097          	auipc	ra,0x0
80001d74:	ae0080e7          	jalr	-1312(ra) # 80001850 <uvmunmap>
  return -1;
80001d78:	fff00513          	li	a0,-1
}
80001d7c:	02c12083          	lw	ra,44(sp)
80001d80:	02812403          	lw	s0,40(sp)
80001d84:	02412483          	lw	s1,36(sp)
80001d88:	02012903          	lw	s2,32(sp)
80001d8c:	01c12983          	lw	s3,28(sp)
80001d90:	01812a03          	lw	s4,24(sp)
80001d94:	01412a83          	lw	s5,20(sp)
80001d98:	01012b03          	lw	s6,16(sp)
80001d9c:	00c12b83          	lw	s7,12(sp)
80001da0:	03010113          	addi	sp,sp,48
80001da4:	00008067          	ret
  return 0;
80001da8:	00000513          	li	a0,0
}
80001dac:	00008067          	ret

80001db0 <uvmclear>:

// mark a PTE invalid for user access.
// used by exec for the user stack guard page.
void
uvmclear(pagetable_t pagetable, uint32 va)
{
80001db0:	ff010113          	addi	sp,sp,-16
80001db4:	00112623          	sw	ra,12(sp)
80001db8:	00812423          	sw	s0,8(sp)
80001dbc:	01010413          	addi	s0,sp,16
  pte_t *pte;
  
  pte = walk(pagetable, va, 0);
80001dc0:	00000613          	li	a2,0
80001dc4:	fffff097          	auipc	ra,0xfffff
80001dc8:	5b0080e7          	jalr	1456(ra) # 80001374 <walk>
  if(pte == 0)
80001dcc:	02050063          	beqz	a0,80001dec <uvmclear+0x3c>
    panic("uvmclear");
  *pte &= ~PTE_U;
80001dd0:	00052783          	lw	a5,0(a0)
80001dd4:	fef7f793          	andi	a5,a5,-17
80001dd8:	00f52023          	sw	a5,0(a0)
}
80001ddc:	00c12083          	lw	ra,12(sp)
80001de0:	00812403          	lw	s0,8(sp)
80001de4:	01010113          	addi	sp,sp,16
80001de8:	00008067          	ret
    panic("uvmclear");
80001dec:	00007517          	auipc	a0,0x7
80001df0:	4dc50513          	addi	a0,a0,1244 # 800092c8 <userret+0x228>
80001df4:	fffff097          	auipc	ra,0xfffff
80001df8:	908080e7          	jalr	-1784(ra) # 800006fc <panic>

80001dfc <copyout>:
int
copyout(pagetable_t pagetable, uint32 dstva, char *src, uint32 len)
{
  uint32 n, va0, pa0;

  while(len > 0){
80001dfc:	0a068663          	beqz	a3,80001ea8 <copyout+0xac>
{
80001e00:	fd010113          	addi	sp,sp,-48
80001e04:	02112623          	sw	ra,44(sp)
80001e08:	02812423          	sw	s0,40(sp)
80001e0c:	02912223          	sw	s1,36(sp)
80001e10:	03212023          	sw	s2,32(sp)
80001e14:	01312e23          	sw	s3,28(sp)
80001e18:	01412c23          	sw	s4,24(sp)
80001e1c:	01512a23          	sw	s5,20(sp)
80001e20:	01612823          	sw	s6,16(sp)
80001e24:	01712623          	sw	s7,12(sp)
80001e28:	01812423          	sw	s8,8(sp)
80001e2c:	03010413          	addi	s0,sp,48
80001e30:	00050b13          	mv	s6,a0
80001e34:	00058c13          	mv	s8,a1
80001e38:	00060a13          	mv	s4,a2
80001e3c:	00068993          	mv	s3,a3
    va0 = PGROUNDDOWN(dstva);
80001e40:	fffffbb7          	lui	s7,0xfffff
    pa0 = walkaddr(pagetable, va0);
    if(pa0 == 0)
      return -1;
    n = PGSIZE - (dstva - va0);
80001e44:	00001ab7          	lui	s5,0x1
80001e48:	02c0006f          	j	80001e74 <copyout+0x78>
    if(n > len)
      n = len;
    memmove((void *)(pa0 + (dstva - va0)), src, n);
80001e4c:	01850533          	add	a0,a0,s8
80001e50:	00048613          	mv	a2,s1
80001e54:	000a0593          	mv	a1,s4
80001e58:	41250533          	sub	a0,a0,s2
80001e5c:	fffff097          	auipc	ra,0xfffff
80001e60:	200080e7          	jalr	512(ra) # 8000105c <memmove>

    len -= n;
80001e64:	409989b3          	sub	s3,s3,s1
    src += n;
80001e68:	009a0a33          	add	s4,s4,s1
    dstva = va0 + PGSIZE;
80001e6c:	01590c33          	add	s8,s2,s5
  while(len > 0){
80001e70:	02098863          	beqz	s3,80001ea0 <copyout+0xa4>
    va0 = PGROUNDDOWN(dstva);
80001e74:	017c7933          	and	s2,s8,s7
    pa0 = walkaddr(pagetable, va0);
80001e78:	00090593          	mv	a1,s2
80001e7c:	000b0513          	mv	a0,s6
80001e80:	fffff097          	auipc	ra,0xfffff
80001e84:	694080e7          	jalr	1684(ra) # 80001514 <walkaddr>
    if(pa0 == 0)
80001e88:	02050463          	beqz	a0,80001eb0 <copyout+0xb4>
    n = PGSIZE - (dstva - va0);
80001e8c:	418904b3          	sub	s1,s2,s8
80001e90:	015484b3          	add	s1,s1,s5
    if(n > len)
80001e94:	fa99fce3          	bgeu	s3,s1,80001e4c <copyout+0x50>
80001e98:	00098493          	mv	s1,s3
80001e9c:	fb1ff06f          	j	80001e4c <copyout+0x50>
  }
  return 0;
80001ea0:	00000513          	li	a0,0
80001ea4:	0100006f          	j	80001eb4 <copyout+0xb8>
80001ea8:	00000513          	li	a0,0
}
80001eac:	00008067          	ret
      return -1;
80001eb0:	fff00513          	li	a0,-1
}
80001eb4:	02c12083          	lw	ra,44(sp)
80001eb8:	02812403          	lw	s0,40(sp)
80001ebc:	02412483          	lw	s1,36(sp)
80001ec0:	02012903          	lw	s2,32(sp)
80001ec4:	01c12983          	lw	s3,28(sp)
80001ec8:	01812a03          	lw	s4,24(sp)
80001ecc:	01412a83          	lw	s5,20(sp)
80001ed0:	01012b03          	lw	s6,16(sp)
80001ed4:	00c12b83          	lw	s7,12(sp)
80001ed8:	00812c03          	lw	s8,8(sp)
80001edc:	03010113          	addi	sp,sp,48
80001ee0:	00008067          	ret

80001ee4 <copyin>:
int
copyin(pagetable_t pagetable, char *dst, uint32 srcva, uint32 len)
{
  uint32 n, va0, pa0;

  while(len > 0){
80001ee4:	0a068663          	beqz	a3,80001f90 <copyin+0xac>
{
80001ee8:	fd010113          	addi	sp,sp,-48
80001eec:	02112623          	sw	ra,44(sp)
80001ef0:	02812423          	sw	s0,40(sp)
80001ef4:	02912223          	sw	s1,36(sp)
80001ef8:	03212023          	sw	s2,32(sp)
80001efc:	01312e23          	sw	s3,28(sp)
80001f00:	01412c23          	sw	s4,24(sp)
80001f04:	01512a23          	sw	s5,20(sp)
80001f08:	01612823          	sw	s6,16(sp)
80001f0c:	01712623          	sw	s7,12(sp)
80001f10:	01812423          	sw	s8,8(sp)
80001f14:	03010413          	addi	s0,sp,48
80001f18:	00050b13          	mv	s6,a0
80001f1c:	00058a13          	mv	s4,a1
80001f20:	00060c13          	mv	s8,a2
80001f24:	00068993          	mv	s3,a3
    va0 = PGROUNDDOWN(srcva);
80001f28:	fffffbb7          	lui	s7,0xfffff
    pa0 = walkaddr(pagetable, va0);
    if(pa0 == 0)
      return -1;
    n = PGSIZE - (srcva - va0);
80001f2c:	00001ab7          	lui	s5,0x1
80001f30:	02c0006f          	j	80001f5c <copyin+0x78>
    if(n > len)
      n = len;
    memmove(dst, (void *)(pa0 + (srcva - va0)), n);
80001f34:	018505b3          	add	a1,a0,s8
80001f38:	00048613          	mv	a2,s1
80001f3c:	412585b3          	sub	a1,a1,s2
80001f40:	000a0513          	mv	a0,s4
80001f44:	fffff097          	auipc	ra,0xfffff
80001f48:	118080e7          	jalr	280(ra) # 8000105c <memmove>

    len -= n;
80001f4c:	409989b3          	sub	s3,s3,s1
    dst += n;
80001f50:	009a0a33          	add	s4,s4,s1
    srcva = va0 + PGSIZE;
80001f54:	01590c33          	add	s8,s2,s5
  while(len > 0){
80001f58:	02098863          	beqz	s3,80001f88 <copyin+0xa4>
    va0 = PGROUNDDOWN(srcva);
80001f5c:	017c7933          	and	s2,s8,s7
    pa0 = walkaddr(pagetable, va0);
80001f60:	00090593          	mv	a1,s2
80001f64:	000b0513          	mv	a0,s6
80001f68:	fffff097          	auipc	ra,0xfffff
80001f6c:	5ac080e7          	jalr	1452(ra) # 80001514 <walkaddr>
    if(pa0 == 0)
80001f70:	02050463          	beqz	a0,80001f98 <copyin+0xb4>
    n = PGSIZE - (srcva - va0);
80001f74:	418904b3          	sub	s1,s2,s8
80001f78:	015484b3          	add	s1,s1,s5
    if(n > len)
80001f7c:	fa99fce3          	bgeu	s3,s1,80001f34 <copyin+0x50>
80001f80:	00098493          	mv	s1,s3
80001f84:	fb1ff06f          	j	80001f34 <copyin+0x50>
  }
  return 0;
80001f88:	00000513          	li	a0,0
80001f8c:	0100006f          	j	80001f9c <copyin+0xb8>
80001f90:	00000513          	li	a0,0
}
80001f94:	00008067          	ret
      return -1;
80001f98:	fff00513          	li	a0,-1
}
80001f9c:	02c12083          	lw	ra,44(sp)
80001fa0:	02812403          	lw	s0,40(sp)
80001fa4:	02412483          	lw	s1,36(sp)
80001fa8:	02012903          	lw	s2,32(sp)
80001fac:	01c12983          	lw	s3,28(sp)
80001fb0:	01812a03          	lw	s4,24(sp)
80001fb4:	01412a83          	lw	s5,20(sp)
80001fb8:	01012b03          	lw	s6,16(sp)
80001fbc:	00c12b83          	lw	s7,12(sp)
80001fc0:	00812c03          	lw	s8,8(sp)
80001fc4:	03010113          	addi	sp,sp,48
80001fc8:	00008067          	ret

80001fcc <copyinstr>:
copyinstr(pagetable_t pagetable, char *dst, uint32 srcva, uint32 max)
{
  uint32 n, va0, pa0;
  int got_null = 0;

  while(got_null == 0 && max > 0){
80001fcc:	10068e63          	beqz	a3,800020e8 <copyinstr+0x11c>
{
80001fd0:	fd010113          	addi	sp,sp,-48
80001fd4:	02112623          	sw	ra,44(sp)
80001fd8:	02812423          	sw	s0,40(sp)
80001fdc:	02912223          	sw	s1,36(sp)
80001fe0:	03212023          	sw	s2,32(sp)
80001fe4:	01312e23          	sw	s3,28(sp)
80001fe8:	01412c23          	sw	s4,24(sp)
80001fec:	01512a23          	sw	s5,20(sp)
80001ff0:	01612823          	sw	s6,16(sp)
80001ff4:	01712623          	sw	s7,12(sp)
80001ff8:	03010413          	addi	s0,sp,48
80001ffc:	00050a93          	mv	s5,a0
80002000:	00058493          	mv	s1,a1
80002004:	00060b93          	mv	s7,a2
80002008:	00068993          	mv	s3,a3
    va0 = PGROUNDDOWN(srcva);
8000200c:	fffffb37          	lui	s6,0xfffff
    pa0 = walkaddr(pagetable, va0);
    if(pa0 == 0)
      return -1;
    n = PGSIZE - (srcva - va0);
80002010:	00001a37          	lui	s4,0x1
80002014:	0540006f          	j	80002068 <copyinstr+0x9c>
      n = max;

    char *p = (char *) (pa0 + (srcva - va0));
    while(n > 0){
      if(*p == '\0'){
        *dst = '\0';
80002018:	00078023          	sb	zero,0(a5) # fffff000 <end+0x7ffdafec>
        got_null = 1;
8000201c:	00100793          	li	a5,1
      dst++;
    }

    srcva = va0 + PGSIZE;
  }
  if(got_null){
80002020:	fff78513          	addi	a0,a5,-1
    return 0;
  } else {
    return -1;
  }
}
80002024:	02c12083          	lw	ra,44(sp)
80002028:	02812403          	lw	s0,40(sp)
8000202c:	02412483          	lw	s1,36(sp)
80002030:	02012903          	lw	s2,32(sp)
80002034:	01c12983          	lw	s3,28(sp)
80002038:	01812a03          	lw	s4,24(sp)
8000203c:	01412a83          	lw	s5,20(sp)
80002040:	01012b03          	lw	s6,16(sp)
80002044:	00c12b83          	lw	s7,12(sp)
80002048:	03010113          	addi	sp,sp,48
8000204c:	00008067          	ret
80002050:	fff98713          	addi	a4,s3,-1 # fff <_entry-0x7ffff001>
80002054:	00e48733          	add	a4,s1,a4
      --max;
80002058:	40b709b3          	sub	s3,a4,a1
    srcva = va0 + PGSIZE;
8000205c:	01490bb3          	add	s7,s2,s4
  while(got_null == 0 && max > 0){
80002060:	06e58463          	beq	a1,a4,800020c8 <copyinstr+0xfc>
{
80002064:	00078493          	mv	s1,a5
    va0 = PGROUNDDOWN(srcva);
80002068:	016bf933          	and	s2,s7,s6
    pa0 = walkaddr(pagetable, va0);
8000206c:	00090593          	mv	a1,s2
80002070:	000a8513          	mv	a0,s5
80002074:	fffff097          	auipc	ra,0xfffff
80002078:	4a0080e7          	jalr	1184(ra) # 80001514 <walkaddr>
    if(pa0 == 0)
8000207c:	04050a63          	beqz	a0,800020d0 <copyinstr+0x104>
    n = PGSIZE - (srcva - va0);
80002080:	417906b3          	sub	a3,s2,s7
80002084:	014686b3          	add	a3,a3,s4
    if(n > max)
80002088:	00d9f463          	bgeu	s3,a3,80002090 <copyinstr+0xc4>
8000208c:	00098693          	mv	a3,s3
    while(n > 0){
80002090:	04068463          	beqz	a3,800020d8 <copyinstr+0x10c>
    char *p = (char *) (pa0 + (srcva - va0));
80002094:	01750633          	add	a2,a0,s7
80002098:	41260633          	sub	a2,a2,s2
8000209c:	00048793          	mv	a5,s1
      if(*p == '\0'){
800020a0:	40960633          	sub	a2,a2,s1
    while(n > 0){
800020a4:	00d486b3          	add	a3,s1,a3
800020a8:	00078593          	mv	a1,a5
      if(*p == '\0'){
800020ac:	00f60733          	add	a4,a2,a5
800020b0:	00074703          	lbu	a4,0(a4) # fffff000 <end+0x7ffdafec>
800020b4:	f60702e3          	beqz	a4,80002018 <copyinstr+0x4c>
        *dst = *p;
800020b8:	00e78023          	sb	a4,0(a5)
      dst++;
800020bc:	00178793          	addi	a5,a5,1
    while(n > 0){
800020c0:	fed794e3          	bne	a5,a3,800020a8 <copyinstr+0xdc>
800020c4:	f8dff06f          	j	80002050 <copyinstr+0x84>
800020c8:	00000793          	li	a5,0
800020cc:	f55ff06f          	j	80002020 <copyinstr+0x54>
      return -1;
800020d0:	fff00513          	li	a0,-1
800020d4:	f51ff06f          	j	80002024 <copyinstr+0x58>
    srcva = va0 + PGSIZE;
800020d8:	00001bb7          	lui	s7,0x1
800020dc:	01790bb3          	add	s7,s2,s7
800020e0:	00048793          	mv	a5,s1
800020e4:	f81ff06f          	j	80002064 <copyinstr+0x98>
  int got_null = 0;
800020e8:	00000793          	li	a5,0
  if(got_null){
800020ec:	fff78513          	addi	a0,a5,-1
}
800020f0:	00008067          	ret

800020f4 <wakeup1>:

// Wake up p if it is sleeping in wait(); used by exit().
// Caller must hold p->lock.
static void
wakeup1(struct proc *p)
{
800020f4:	ff010113          	addi	sp,sp,-16
800020f8:	00112623          	sw	ra,12(sp)
800020fc:	00812423          	sw	s0,8(sp)
80002100:	00912223          	sw	s1,4(sp)
80002104:	01010413          	addi	s0,sp,16
80002108:	00050493          	mv	s1,a0
  if(!holding(&p->lock))
8000210c:	fffff097          	auipc	ra,0xfffff
80002110:	d8c080e7          	jalr	-628(ra) # 80000e98 <holding>
80002114:	02050063          	beqz	a0,80002134 <wakeup1+0x40>
    panic("wakeup1");
  if(p->chan == p && p->state == SLEEPING) {
80002118:	0144a783          	lw	a5,20(s1)
8000211c:	02978463          	beq	a5,s1,80002144 <wakeup1+0x50>
    p->state = RUNNABLE;
  }
}
80002120:	00c12083          	lw	ra,12(sp)
80002124:	00812403          	lw	s0,8(sp)
80002128:	00412483          	lw	s1,4(sp)
8000212c:	01010113          	addi	sp,sp,16
80002130:	00008067          	ret
    panic("wakeup1");
80002134:	00007517          	auipc	a0,0x7
80002138:	1a050513          	addi	a0,a0,416 # 800092d4 <userret+0x234>
8000213c:	ffffe097          	auipc	ra,0xffffe
80002140:	5c0080e7          	jalr	1472(ra) # 800006fc <panic>
  if(p->chan == p && p->state == SLEEPING) {
80002144:	00c4a703          	lw	a4,12(s1)
80002148:	00100793          	li	a5,1
8000214c:	fcf71ae3          	bne	a4,a5,80002120 <wakeup1+0x2c>
    p->state = RUNNABLE;
80002150:	00200793          	li	a5,2
80002154:	00f4a623          	sw	a5,12(s1)
}
80002158:	fc9ff06f          	j	80002120 <wakeup1+0x2c>

8000215c <procinit>:
{
8000215c:	fd010113          	addi	sp,sp,-48
80002160:	02112623          	sw	ra,44(sp)
80002164:	02812423          	sw	s0,40(sp)
80002168:	02912223          	sw	s1,36(sp)
8000216c:	03212023          	sw	s2,32(sp)
80002170:	01312e23          	sw	s3,28(sp)
80002174:	01412c23          	sw	s4,24(sp)
80002178:	01512a23          	sw	s5,20(sp)
8000217c:	01612823          	sw	s6,16(sp)
80002180:	01712623          	sw	s7,12(sp)
80002184:	01812423          	sw	s8,8(sp)
80002188:	01912223          	sw	s9,4(sp)
8000218c:	03010413          	addi	s0,sp,48
  initlock(&pid_lock, "nextpid");
80002190:	00007597          	auipc	a1,0x7
80002194:	14c58593          	addi	a1,a1,332 # 800092dc <userret+0x23c>
80002198:	00011517          	auipc	a0,0x11
8000219c:	32050513          	addi	a0,a0,800 # 800134b8 <pid_lock>
800021a0:	fffff097          	auipc	ra,0xfffff
800021a4:	bcc080e7          	jalr	-1076(ra) # 80000d6c <initlock>
  for(p = proc; p < &proc[NPROC]; p++) {
800021a8:	00011917          	auipc	s2,0x11
800021ac:	53c90913          	addi	s2,s2,1340 # 800136e4 <proc>
      initlock(&p->lock, "proc");
800021b0:	00007c97          	auipc	s9,0x7
800021b4:	134c8c93          	addi	s9,s9,308 # 800092e4 <userret+0x244>
      uint32 va = KSTACK((int) (p - proc));
800021b8:	00090c13          	mv	s8,s2
800021bc:	aaaab9b7          	lui	s3,0xaaaab
800021c0:	aab98993          	addi	s3,s3,-1365 # aaaaaaab <end+0x2aa86a97>
800021c4:	fffffbb7          	lui	s7,0xfffff
      kvmmap(va, (uint32)pa, PGSIZE, PTE_R | PTE_W);
800021c8:	00600b13          	li	s6,6
800021cc:	00001ab7          	lui	s5,0x1
  for(p = proc; p < &proc[NPROC]; p++) {
800021d0:	00014a17          	auipc	s4,0x14
800021d4:	514a0a13          	addi	s4,s4,1300 # 800166e4 <tickslock>
      initlock(&p->lock, "proc");
800021d8:	000c8593          	mv	a1,s9
800021dc:	00090513          	mv	a0,s2
800021e0:	fffff097          	auipc	ra,0xfffff
800021e4:	b8c080e7          	jalr	-1140(ra) # 80000d6c <initlock>
      char *pa = kalloc();
800021e8:	fffff097          	auipc	ra,0xfffff
800021ec:	af8080e7          	jalr	-1288(ra) # 80000ce0 <kalloc>
800021f0:	00050593          	mv	a1,a0
      if(pa == 0)
800021f4:	06050c63          	beqz	a0,8000226c <procinit+0x110>
      uint32 va = KSTACK((int) (p - proc));
800021f8:	418904b3          	sub	s1,s2,s8
800021fc:	4064d493          	srai	s1,s1,0x6
80002200:	033484b3          	mul	s1,s1,s3
80002204:	00148493          	addi	s1,s1,1
80002208:	00d49493          	slli	s1,s1,0xd
8000220c:	409b84b3          	sub	s1,s7,s1
      kvmmap(va, (uint32)pa, PGSIZE, PTE_R | PTE_W);
80002210:	000b0693          	mv	a3,s6
80002214:	000a8613          	mv	a2,s5
80002218:	00048513          	mv	a0,s1
8000221c:	fffff097          	auipc	ra,0xfffff
80002220:	4c8080e7          	jalr	1224(ra) # 800016e4 <kvmmap>
      p->kstack = va;
80002224:	02992223          	sw	s1,36(s2)
  for(p = proc; p < &proc[NPROC]; p++) {
80002228:	0c090913          	addi	s2,s2,192
8000222c:	fb4916e3          	bne	s2,s4,800021d8 <procinit+0x7c>
  kvminithart();
80002230:	fffff097          	auipc	ra,0xfffff
80002234:	2a8080e7          	jalr	680(ra) # 800014d8 <kvminithart>
}
80002238:	02c12083          	lw	ra,44(sp)
8000223c:	02812403          	lw	s0,40(sp)
80002240:	02412483          	lw	s1,36(sp)
80002244:	02012903          	lw	s2,32(sp)
80002248:	01c12983          	lw	s3,28(sp)
8000224c:	01812a03          	lw	s4,24(sp)
80002250:	01412a83          	lw	s5,20(sp)
80002254:	01012b03          	lw	s6,16(sp)
80002258:	00c12b83          	lw	s7,12(sp)
8000225c:	00812c03          	lw	s8,8(sp)
80002260:	00412c83          	lw	s9,4(sp)
80002264:	03010113          	addi	sp,sp,48
80002268:	00008067          	ret
        panic("kalloc");
8000226c:	00007517          	auipc	a0,0x7
80002270:	08050513          	addi	a0,a0,128 # 800092ec <userret+0x24c>
80002274:	ffffe097          	auipc	ra,0xffffe
80002278:	488080e7          	jalr	1160(ra) # 800006fc <panic>

8000227c <cpuid>:
{
8000227c:	ff010113          	addi	sp,sp,-16
80002280:	00112623          	sw	ra,12(sp)
80002284:	00812423          	sw	s0,8(sp)
80002288:	01010413          	addi	s0,sp,16
  asm volatile("mv %0, tp" : "=r" (x) );
8000228c:	00020513          	mv	a0,tp
}
80002290:	00c12083          	lw	ra,12(sp)
80002294:	00812403          	lw	s0,8(sp)
80002298:	01010113          	addi	sp,sp,16
8000229c:	00008067          	ret

800022a0 <mycpu>:
mycpu(void) {
800022a0:	ff010113          	addi	sp,sp,-16
800022a4:	00112623          	sw	ra,12(sp)
800022a8:	00812423          	sw	s0,8(sp)
800022ac:	01010413          	addi	s0,sp,16
800022b0:	00020713          	mv	a4,tp
  struct cpu *c = &cpus[id];
800022b4:	00471793          	slli	a5,a4,0x4
800022b8:	00e787b3          	add	a5,a5,a4
800022bc:	00279793          	slli	a5,a5,0x2
}
800022c0:	00011517          	auipc	a0,0x11
800022c4:	20450513          	addi	a0,a0,516 # 800134c4 <cpus>
800022c8:	00f50533          	add	a0,a0,a5
800022cc:	00c12083          	lw	ra,12(sp)
800022d0:	00812403          	lw	s0,8(sp)
800022d4:	01010113          	addi	sp,sp,16
800022d8:	00008067          	ret

800022dc <myproc>:
myproc(void) {
800022dc:	ff010113          	addi	sp,sp,-16
800022e0:	00112623          	sw	ra,12(sp)
800022e4:	00812423          	sw	s0,8(sp)
800022e8:	00912223          	sw	s1,4(sp)
800022ec:	01010413          	addi	s0,sp,16
  push_off();
800022f0:	fffff097          	auipc	ra,0xfffff
800022f4:	aa8080e7          	jalr	-1368(ra) # 80000d98 <push_off>
800022f8:	00020713          	mv	a4,tp
  struct proc *p = c->proc;
800022fc:	00471793          	slli	a5,a4,0x4
80002300:	00e787b3          	add	a5,a5,a4
80002304:	00279793          	slli	a5,a5,0x2
80002308:	00011717          	auipc	a4,0x11
8000230c:	1b070713          	addi	a4,a4,432 # 800134b8 <pid_lock>
80002310:	00f707b3          	add	a5,a4,a5
80002314:	00c7a783          	lw	a5,12(a5)
80002318:	00078493          	mv	s1,a5
  pop_off();
8000231c:	fffff097          	auipc	ra,0xfffff
80002320:	af4080e7          	jalr	-1292(ra) # 80000e10 <pop_off>
}
80002324:	00048513          	mv	a0,s1
80002328:	00c12083          	lw	ra,12(sp)
8000232c:	00812403          	lw	s0,8(sp)
80002330:	00412483          	lw	s1,4(sp)
80002334:	01010113          	addi	sp,sp,16
80002338:	00008067          	ret

8000233c <forkret>:
{
8000233c:	ff010113          	addi	sp,sp,-16
80002340:	00112623          	sw	ra,12(sp)
80002344:	00812423          	sw	s0,8(sp)
80002348:	01010413          	addi	s0,sp,16
  release(&myproc()->lock);
8000234c:	00000097          	auipc	ra,0x0
80002350:	f90080e7          	jalr	-112(ra) # 800022dc <myproc>
80002354:	fffff097          	auipc	ra,0xfffff
80002358:	c1c080e7          	jalr	-996(ra) # 80000f70 <release>
  if (first) {
8000235c:	00008797          	auipc	a5,0x8
80002360:	d047a783          	lw	a5,-764(a5) # 8000a060 <first.1>
80002364:	00079e63          	bnez	a5,80002380 <forkret+0x44>
  usertrapret();
80002368:	00001097          	auipc	ra,0x1
8000236c:	ff4080e7          	jalr	-12(ra) # 8000335c <usertrapret>
}
80002370:	00c12083          	lw	ra,12(sp)
80002374:	00812403          	lw	s0,8(sp)
80002378:	01010113          	addi	sp,sp,16
8000237c:	00008067          	ret
    first = 0;
80002380:	00008797          	auipc	a5,0x8
80002384:	ce07a023          	sw	zero,-800(a5) # 8000a060 <first.1>
    fsinit(ROOTDEV);
80002388:	00100513          	li	a0,1
8000238c:	00002097          	auipc	ra,0x2
80002390:	1e4080e7          	jalr	484(ra) # 80004570 <fsinit>
80002394:	fd5ff06f          	j	80002368 <forkret+0x2c>

80002398 <allocpid>:
allocpid() {
80002398:	ff010113          	addi	sp,sp,-16
8000239c:	00112623          	sw	ra,12(sp)
800023a0:	00812423          	sw	s0,8(sp)
800023a4:	00912223          	sw	s1,4(sp)
800023a8:	01010413          	addi	s0,sp,16
  acquire(&pid_lock);
800023ac:	00011517          	auipc	a0,0x11
800023b0:	10c50513          	addi	a0,a0,268 # 800134b8 <pid_lock>
800023b4:	fffff097          	auipc	ra,0xfffff
800023b8:	b48080e7          	jalr	-1208(ra) # 80000efc <acquire>
  pid = nextpid;
800023bc:	00008797          	auipc	a5,0x8
800023c0:	ca878793          	addi	a5,a5,-856 # 8000a064 <nextpid>
800023c4:	0007a483          	lw	s1,0(a5)
  nextpid = nextpid + 1;
800023c8:	00148713          	addi	a4,s1,1
800023cc:	00e7a023          	sw	a4,0(a5)
  release(&pid_lock);
800023d0:	00011517          	auipc	a0,0x11
800023d4:	0e850513          	addi	a0,a0,232 # 800134b8 <pid_lock>
800023d8:	fffff097          	auipc	ra,0xfffff
800023dc:	b98080e7          	jalr	-1128(ra) # 80000f70 <release>
}
800023e0:	00048513          	mv	a0,s1
800023e4:	00c12083          	lw	ra,12(sp)
800023e8:	00812403          	lw	s0,8(sp)
800023ec:	00412483          	lw	s1,4(sp)
800023f0:	01010113          	addi	sp,sp,16
800023f4:	00008067          	ret

800023f8 <proc_pagetable>:
{
800023f8:	ff010113          	addi	sp,sp,-16
800023fc:	00112623          	sw	ra,12(sp)
80002400:	00812423          	sw	s0,8(sp)
80002404:	00912223          	sw	s1,4(sp)
80002408:	01212023          	sw	s2,0(sp)
8000240c:	01010413          	addi	s0,sp,16
80002410:	00050913          	mv	s2,a0
  pagetable = uvmcreate();
80002414:	fffff097          	auipc	ra,0xfffff
80002418:	554080e7          	jalr	1364(ra) # 80001968 <uvmcreate>
8000241c:	00050493          	mv	s1,a0
  mappages(pagetable, TRAMPOLINE, PGSIZE,
80002420:	00a00713          	li	a4,10
80002424:	00007697          	auipc	a3,0x7
80002428:	bdc68693          	addi	a3,a3,-1060 # 80009000 <trampoline>
8000242c:	00001637          	lui	a2,0x1
80002430:	fffff5b7          	lui	a1,0xfffff
80002434:	fffff097          	auipc	ra,0xfffff
80002438:	1c8080e7          	jalr	456(ra) # 800015fc <mappages>
  mappages(pagetable, TRAPFRAME, PGSIZE,
8000243c:	00600713          	li	a4,6
80002440:	03092683          	lw	a3,48(s2)
80002444:	00001637          	lui	a2,0x1
80002448:	ffffe5b7          	lui	a1,0xffffe
8000244c:	00048513          	mv	a0,s1
80002450:	fffff097          	auipc	ra,0xfffff
80002454:	1ac080e7          	jalr	428(ra) # 800015fc <mappages>
}
80002458:	00048513          	mv	a0,s1
8000245c:	00c12083          	lw	ra,12(sp)
80002460:	00812403          	lw	s0,8(sp)
80002464:	00412483          	lw	s1,4(sp)
80002468:	00012903          	lw	s2,0(sp)
8000246c:	01010113          	addi	sp,sp,16
80002470:	00008067          	ret

80002474 <allocproc>:
{
80002474:	ff010113          	addi	sp,sp,-16
80002478:	00112623          	sw	ra,12(sp)
8000247c:	00812423          	sw	s0,8(sp)
80002480:	00912223          	sw	s1,4(sp)
80002484:	01212023          	sw	s2,0(sp)
80002488:	01010413          	addi	s0,sp,16
  for(p = proc; p < &proc[NPROC]; p++) {
8000248c:	00011497          	auipc	s1,0x11
80002490:	25848493          	addi	s1,s1,600 # 800136e4 <proc>
80002494:	00014917          	auipc	s2,0x14
80002498:	25090913          	addi	s2,s2,592 # 800166e4 <tickslock>
    acquire(&p->lock);
8000249c:	00048513          	mv	a0,s1
800024a0:	fffff097          	auipc	ra,0xfffff
800024a4:	a5c080e7          	jalr	-1444(ra) # 80000efc <acquire>
    if(p->state == UNUSED) {
800024a8:	00c4a783          	lw	a5,12(s1)
800024ac:	02078063          	beqz	a5,800024cc <allocproc+0x58>
      release(&p->lock);
800024b0:	00048513          	mv	a0,s1
800024b4:	fffff097          	auipc	ra,0xfffff
800024b8:	abc080e7          	jalr	-1348(ra) # 80000f70 <release>
  for(p = proc; p < &proc[NPROC]; p++) {
800024bc:	0c048493          	addi	s1,s1,192
800024c0:	fd249ee3          	bne	s1,s2,8000249c <allocproc+0x28>
  return 0;
800024c4:	00000493          	li	s1,0
800024c8:	0640006f          	j	8000252c <allocproc+0xb8>
  p->pid = allocpid();
800024cc:	00000097          	auipc	ra,0x0
800024d0:	ecc080e7          	jalr	-308(ra) # 80002398 <allocpid>
800024d4:	02a4a023          	sw	a0,32(s1)
  if((p->tf = (struct trapframe *)kalloc()) == 0){
800024d8:	fffff097          	auipc	ra,0xfffff
800024dc:	808080e7          	jalr	-2040(ra) # 80000ce0 <kalloc>
800024e0:	00050913          	mv	s2,a0
800024e4:	02a4a823          	sw	a0,48(s1)
800024e8:	06050063          	beqz	a0,80002548 <allocproc+0xd4>
  p->pagetable = proc_pagetable(p);
800024ec:	00048513          	mv	a0,s1
800024f0:	00000097          	auipc	ra,0x0
800024f4:	f08080e7          	jalr	-248(ra) # 800023f8 <proc_pagetable>
800024f8:	02a4a623          	sw	a0,44(s1)
  memset(&p->context, 0, sizeof p->context);
800024fc:	03800613          	li	a2,56
80002500:	00000593          	li	a1,0
80002504:	03448513          	addi	a0,s1,52
80002508:	fffff097          	auipc	ra,0xfffff
8000250c:	ac8080e7          	jalr	-1336(ra) # 80000fd0 <memset>
  p->context.ra = (uint32)forkret;
80002510:	00000797          	auipc	a5,0x0
80002514:	e2c78793          	addi	a5,a5,-468 # 8000233c <forkret>
80002518:	02f4aa23          	sw	a5,52(s1)
  p->context.sp = p->kstack + PGSIZE;
8000251c:	0244a783          	lw	a5,36(s1)
80002520:	00001737          	lui	a4,0x1
80002524:	00e787b3          	add	a5,a5,a4
80002528:	02f4ac23          	sw	a5,56(s1)
}
8000252c:	00048513          	mv	a0,s1
80002530:	00c12083          	lw	ra,12(sp)
80002534:	00812403          	lw	s0,8(sp)
80002538:	00412483          	lw	s1,4(sp)
8000253c:	00012903          	lw	s2,0(sp)
80002540:	01010113          	addi	sp,sp,16
80002544:	00008067          	ret
    release(&p->lock);
80002548:	00048513          	mv	a0,s1
8000254c:	fffff097          	auipc	ra,0xfffff
80002550:	a24080e7          	jalr	-1500(ra) # 80000f70 <release>
    return 0;
80002554:	00090493          	mv	s1,s2
80002558:	fd5ff06f          	j	8000252c <allocproc+0xb8>

8000255c <proc_freepagetable>:
{
8000255c:	ff010113          	addi	sp,sp,-16
80002560:	00112623          	sw	ra,12(sp)
80002564:	00812423          	sw	s0,8(sp)
80002568:	00912223          	sw	s1,4(sp)
8000256c:	01212023          	sw	s2,0(sp)
80002570:	01010413          	addi	s0,sp,16
80002574:	00050913          	mv	s2,a0
80002578:	00058493          	mv	s1,a1
  uvmunmap(pagetable, TRAMPOLINE, PGSIZE, 0);
8000257c:	00000693          	li	a3,0
80002580:	00001637          	lui	a2,0x1
80002584:	fffff5b7          	lui	a1,0xfffff
80002588:	fffff097          	auipc	ra,0xfffff
8000258c:	2c8080e7          	jalr	712(ra) # 80001850 <uvmunmap>
  uvmunmap(pagetable, TRAPFRAME, PGSIZE, 0);
80002590:	00000693          	li	a3,0
80002594:	00001637          	lui	a2,0x1
80002598:	ffffe5b7          	lui	a1,0xffffe
8000259c:	00090513          	mv	a0,s2
800025a0:	fffff097          	auipc	ra,0xfffff
800025a4:	2b0080e7          	jalr	688(ra) # 80001850 <uvmunmap>
  if(sz > 0)
800025a8:	00049e63          	bnez	s1,800025c4 <proc_freepagetable+0x68>
}
800025ac:	00c12083          	lw	ra,12(sp)
800025b0:	00812403          	lw	s0,8(sp)
800025b4:	00412483          	lw	s1,4(sp)
800025b8:	00012903          	lw	s2,0(sp)
800025bc:	01010113          	addi	sp,sp,16
800025c0:	00008067          	ret
    uvmfree(pagetable, sz);
800025c4:	00048593          	mv	a1,s1
800025c8:	00090513          	mv	a0,s2
800025cc:	fffff097          	auipc	ra,0xfffff
800025d0:	664080e7          	jalr	1636(ra) # 80001c30 <uvmfree>
}
800025d4:	fd9ff06f          	j	800025ac <proc_freepagetable+0x50>

800025d8 <freeproc>:
{
800025d8:	ff010113          	addi	sp,sp,-16
800025dc:	00112623          	sw	ra,12(sp)
800025e0:	00812423          	sw	s0,8(sp)
800025e4:	00912223          	sw	s1,4(sp)
800025e8:	01010413          	addi	s0,sp,16
800025ec:	00050493          	mv	s1,a0
  if(p->tf)
800025f0:	03052503          	lw	a0,48(a0)
800025f4:	00050663          	beqz	a0,80002600 <freeproc+0x28>
    kfree((void*)p->tf);
800025f8:	ffffe097          	auipc	ra,0xffffe
800025fc:	578080e7          	jalr	1400(ra) # 80000b70 <kfree>
  p->tf = 0;
80002600:	0204a823          	sw	zero,48(s1)
  if(p->pagetable)
80002604:	02c4a503          	lw	a0,44(s1)
80002608:	00050863          	beqz	a0,80002618 <freeproc+0x40>
    proc_freepagetable(p->pagetable, p->sz);
8000260c:	0284a583          	lw	a1,40(s1)
80002610:	00000097          	auipc	ra,0x0
80002614:	f4c080e7          	jalr	-180(ra) # 8000255c <proc_freepagetable>
  p->pagetable = 0;
80002618:	0204a623          	sw	zero,44(s1)
  p->sz = 0;
8000261c:	0204a423          	sw	zero,40(s1)
  p->pid = 0;
80002620:	0204a023          	sw	zero,32(s1)
  p->parent = 0;
80002624:	0004a823          	sw	zero,16(s1)
  p->name[0] = 0;
80002628:	0a048823          	sb	zero,176(s1)
  p->chan = 0;
8000262c:	0004aa23          	sw	zero,20(s1)
  p->killed = 0;
80002630:	0004ac23          	sw	zero,24(s1)
  p->xstate = 0;
80002634:	0004ae23          	sw	zero,28(s1)
  p->state = UNUSED;
80002638:	0004a623          	sw	zero,12(s1)
}
8000263c:	00c12083          	lw	ra,12(sp)
80002640:	00812403          	lw	s0,8(sp)
80002644:	00412483          	lw	s1,4(sp)
80002648:	01010113          	addi	sp,sp,16
8000264c:	00008067          	ret

80002650 <userinit>:
{
80002650:	ff010113          	addi	sp,sp,-16
80002654:	00112623          	sw	ra,12(sp)
80002658:	00812423          	sw	s0,8(sp)
8000265c:	00912223          	sw	s1,4(sp)
80002660:	01010413          	addi	s0,sp,16
  p = allocproc();
80002664:	00000097          	auipc	ra,0x0
80002668:	e10080e7          	jalr	-496(ra) # 80002474 <allocproc>
8000266c:	00050493          	mv	s1,a0
  initproc = p;
80002670:	00022797          	auipc	a5,0x22
80002674:	98a7ae23          	sw	a0,-1636(a5) # 8002400c <initproc>
  uvminit(p->pagetable, initcode, sizeof(initcode));
80002678:	06000613          	li	a2,96
8000267c:	00008597          	auipc	a1,0x8
80002680:	98458593          	addi	a1,a1,-1660 # 8000a000 <initcode>
80002684:	02c52503          	lw	a0,44(a0)
80002688:	fffff097          	auipc	ra,0xfffff
8000268c:	33c080e7          	jalr	828(ra) # 800019c4 <uvminit>
  p->sz = PGSIZE;
80002690:	000017b7          	lui	a5,0x1
80002694:	02f4a423          	sw	a5,40(s1)
  p->tf->epc = 0;      // user program counter
80002698:	0304a703          	lw	a4,48(s1)
8000269c:	00072623          	sw	zero,12(a4) # 100c <_entry-0x7fffeff4>
  p->tf->sp = PGSIZE;  // user stack pointer
800026a0:	0304a703          	lw	a4,48(s1)
800026a4:	00f72c23          	sw	a5,24(a4)
  safestrcpy(p->name, "initcode", sizeof(p->name));
800026a8:	01000613          	li	a2,16
800026ac:	00007597          	auipc	a1,0x7
800026b0:	c4858593          	addi	a1,a1,-952 # 800092f4 <userret+0x254>
800026b4:	0b048513          	addi	a0,s1,176
800026b8:	fffff097          	auipc	ra,0xfffff
800026bc:	b00080e7          	jalr	-1280(ra) # 800011b8 <safestrcpy>
  p->cwd = namei("/");
800026c0:	00007517          	auipc	a0,0x7
800026c4:	c4050513          	addi	a0,a0,-960 # 80009300 <userret+0x260>
800026c8:	00003097          	auipc	ra,0x3
800026cc:	cec080e7          	jalr	-788(ra) # 800053b4 <namei>
800026d0:	0aa4a623          	sw	a0,172(s1)
  p->state = RUNNABLE;
800026d4:	00200793          	li	a5,2
800026d8:	00f4a623          	sw	a5,12(s1)
  release(&p->lock);
800026dc:	00048513          	mv	a0,s1
800026e0:	fffff097          	auipc	ra,0xfffff
800026e4:	890080e7          	jalr	-1904(ra) # 80000f70 <release>
}
800026e8:	00c12083          	lw	ra,12(sp)
800026ec:	00812403          	lw	s0,8(sp)
800026f0:	00412483          	lw	s1,4(sp)
800026f4:	01010113          	addi	sp,sp,16
800026f8:	00008067          	ret

800026fc <growproc>:
{
800026fc:	ff010113          	addi	sp,sp,-16
80002700:	00112623          	sw	ra,12(sp)
80002704:	00812423          	sw	s0,8(sp)
80002708:	00912223          	sw	s1,4(sp)
8000270c:	01212023          	sw	s2,0(sp)
80002710:	01010413          	addi	s0,sp,16
80002714:	00050913          	mv	s2,a0
  struct proc *p = myproc();
80002718:	00000097          	auipc	ra,0x0
8000271c:	bc4080e7          	jalr	-1084(ra) # 800022dc <myproc>
80002720:	00050493          	mv	s1,a0
  sz = p->sz;
80002724:	02852583          	lw	a1,40(a0)
  if(n > 0){
80002728:	03204463          	bgtz	s2,80002750 <growproc+0x54>
  } else if(n < 0){
8000272c:	04094263          	bltz	s2,80002770 <growproc+0x74>
  p->sz = sz;
80002730:	02b4a423          	sw	a1,40(s1)
  return 0;
80002734:	00000513          	li	a0,0
}
80002738:	00c12083          	lw	ra,12(sp)
8000273c:	00812403          	lw	s0,8(sp)
80002740:	00412483          	lw	s1,4(sp)
80002744:	00012903          	lw	s2,0(sp)
80002748:	01010113          	addi	sp,sp,16
8000274c:	00008067          	ret
    if((sz = uvmalloc(p->pagetable, sz, sz + n)) == 0) {
80002750:	00b90633          	add	a2,s2,a1
80002754:	02c52503          	lw	a0,44(a0)
80002758:	fffff097          	auipc	ra,0xfffff
8000275c:	38c080e7          	jalr	908(ra) # 80001ae4 <uvmalloc>
80002760:	00050593          	mv	a1,a0
80002764:	fc0516e3          	bnez	a0,80002730 <growproc+0x34>
      return -1;
80002768:	fff00513          	li	a0,-1
8000276c:	fcdff06f          	j	80002738 <growproc+0x3c>
    sz = uvmdealloc(p->pagetable, sz, sz + n);
80002770:	00b90633          	add	a2,s2,a1
80002774:	02c52503          	lw	a0,44(a0)
80002778:	fffff097          	auipc	ra,0xfffff
8000277c:	2fc080e7          	jalr	764(ra) # 80001a74 <uvmdealloc>
80002780:	00050593          	mv	a1,a0
80002784:	fadff06f          	j	80002730 <growproc+0x34>

80002788 <fork>:
{
80002788:	fe010113          	addi	sp,sp,-32
8000278c:	00112e23          	sw	ra,28(sp)
80002790:	00812c23          	sw	s0,24(sp)
80002794:	00912a23          	sw	s1,20(sp)
80002798:	01512223          	sw	s5,4(sp)
8000279c:	02010413          	addi	s0,sp,32
  struct proc *p = myproc();
800027a0:	00000097          	auipc	ra,0x0
800027a4:	b3c080e7          	jalr	-1220(ra) # 800022dc <myproc>
800027a8:	00050a93          	mv	s5,a0
  if((np = allocproc()) == 0){
800027ac:	00000097          	auipc	ra,0x0
800027b0:	cc8080e7          	jalr	-824(ra) # 80002474 <allocproc>
800027b4:	12050c63          	beqz	a0,800028ec <fork+0x164>
800027b8:	01412423          	sw	s4,8(sp)
800027bc:	00050a13          	mv	s4,a0
  if(uvmcopy(p->pagetable, np->pagetable, p->sz) < 0){
800027c0:	028aa603          	lw	a2,40(s5) # 1028 <_entry-0x7fffefd8>
800027c4:	02c52583          	lw	a1,44(a0)
800027c8:	02caa503          	lw	a0,44(s5)
800027cc:	fffff097          	auipc	ra,0xfffff
800027d0:	4b0080e7          	jalr	1200(ra) # 80001c7c <uvmcopy>
800027d4:	06054663          	bltz	a0,80002840 <fork+0xb8>
800027d8:	01212823          	sw	s2,16(sp)
800027dc:	01312623          	sw	s3,12(sp)
  np->sz = p->sz;
800027e0:	028aa783          	lw	a5,40(s5)
800027e4:	02fa2423          	sw	a5,40(s4)
  np->parent = p;
800027e8:	015a2823          	sw	s5,16(s4)
  *(np->tf) = *(p->tf);
800027ec:	030aa683          	lw	a3,48(s5)
800027f0:	00068793          	mv	a5,a3
800027f4:	030a2703          	lw	a4,48(s4)
800027f8:	09068693          	addi	a3,a3,144
800027fc:	0007a503          	lw	a0,0(a5) # 1000 <_entry-0x7ffff000>
80002800:	0047a583          	lw	a1,4(a5)
80002804:	0087a603          	lw	a2,8(a5)
80002808:	00a72023          	sw	a0,0(a4)
8000280c:	00b72223          	sw	a1,4(a4)
80002810:	00c72423          	sw	a2,8(a4)
80002814:	00c7a603          	lw	a2,12(a5)
80002818:	00c72623          	sw	a2,12(a4)
8000281c:	01078793          	addi	a5,a5,16
80002820:	01070713          	addi	a4,a4,16
80002824:	fcd79ce3          	bne	a5,a3,800027fc <fork+0x74>
  np->tf->a0 = 0;
80002828:	030a2783          	lw	a5,48(s4)
8000282c:	0207ac23          	sw	zero,56(a5)
  for(i = 0; i < NOFILE; i++)
80002830:	06ca8493          	addi	s1,s5,108
80002834:	06ca0913          	addi	s2,s4,108
80002838:	0aca8993          	addi	s3,s5,172
8000283c:	0340006f          	j	80002870 <fork+0xe8>
    freeproc(np);
80002840:	000a0513          	mv	a0,s4
80002844:	00000097          	auipc	ra,0x0
80002848:	d94080e7          	jalr	-620(ra) # 800025d8 <freeproc>
    release(&np->lock);
8000284c:	000a0513          	mv	a0,s4
80002850:	ffffe097          	auipc	ra,0xffffe
80002854:	720080e7          	jalr	1824(ra) # 80000f70 <release>
    return -1;
80002858:	fff00493          	li	s1,-1
8000285c:	00812a03          	lw	s4,8(sp)
80002860:	0700006f          	j	800028d0 <fork+0x148>
  for(i = 0; i < NOFILE; i++)
80002864:	00448493          	addi	s1,s1,4
80002868:	00490913          	addi	s2,s2,4
8000286c:	01348e63          	beq	s1,s3,80002888 <fork+0x100>
    if(p->ofile[i])
80002870:	0004a503          	lw	a0,0(s1)
80002874:	fe0508e3          	beqz	a0,80002864 <fork+0xdc>
      np->ofile[i] = filedup(p->ofile[i]);
80002878:	00003097          	auipc	ra,0x3
8000287c:	42c080e7          	jalr	1068(ra) # 80005ca4 <filedup>
80002880:	00a92023          	sw	a0,0(s2)
80002884:	fe1ff06f          	j	80002864 <fork+0xdc>
  np->cwd = idup(p->cwd);
80002888:	0acaa503          	lw	a0,172(s5)
8000288c:	00002097          	auipc	ra,0x2
80002890:	fd0080e7          	jalr	-48(ra) # 8000485c <idup>
80002894:	0aaa2623          	sw	a0,172(s4)
  safestrcpy(np->name, p->name, sizeof(p->name));
80002898:	01000613          	li	a2,16
8000289c:	0b0a8593          	addi	a1,s5,176
800028a0:	0b0a0513          	addi	a0,s4,176
800028a4:	fffff097          	auipc	ra,0xfffff
800028a8:	914080e7          	jalr	-1772(ra) # 800011b8 <safestrcpy>
  pid = np->pid;
800028ac:	020a2483          	lw	s1,32(s4)
  np->state = RUNNABLE;
800028b0:	00200793          	li	a5,2
800028b4:	00fa2623          	sw	a5,12(s4)
  release(&np->lock);
800028b8:	000a0513          	mv	a0,s4
800028bc:	ffffe097          	auipc	ra,0xffffe
800028c0:	6b4080e7          	jalr	1716(ra) # 80000f70 <release>
  return pid;
800028c4:	01012903          	lw	s2,16(sp)
800028c8:	00c12983          	lw	s3,12(sp)
800028cc:	00812a03          	lw	s4,8(sp)
}
800028d0:	00048513          	mv	a0,s1
800028d4:	01c12083          	lw	ra,28(sp)
800028d8:	01812403          	lw	s0,24(sp)
800028dc:	01412483          	lw	s1,20(sp)
800028e0:	00412a83          	lw	s5,4(sp)
800028e4:	02010113          	addi	sp,sp,32
800028e8:	00008067          	ret
    return -1;
800028ec:	fff00493          	li	s1,-1
800028f0:	fe1ff06f          	j	800028d0 <fork+0x148>

800028f4 <reparent>:
{
800028f4:	fe010113          	addi	sp,sp,-32
800028f8:	00112e23          	sw	ra,28(sp)
800028fc:	00812c23          	sw	s0,24(sp)
80002900:	00912a23          	sw	s1,20(sp)
80002904:	01212823          	sw	s2,16(sp)
80002908:	01312623          	sw	s3,12(sp)
8000290c:	01412423          	sw	s4,8(sp)
80002910:	02010413          	addi	s0,sp,32
80002914:	00050913          	mv	s2,a0
  for(pp = proc; pp < &proc[NPROC]; pp++){
80002918:	00011497          	auipc	s1,0x11
8000291c:	dcc48493          	addi	s1,s1,-564 # 800136e4 <proc>
      pp->parent = initproc;
80002920:	00021a17          	auipc	s4,0x21
80002924:	6eca0a13          	addi	s4,s4,1772 # 8002400c <initproc>
  for(pp = proc; pp < &proc[NPROC]; pp++){
80002928:	00014997          	auipc	s3,0x14
8000292c:	dbc98993          	addi	s3,s3,-580 # 800166e4 <tickslock>
80002930:	00c0006f          	j	8000293c <reparent+0x48>
80002934:	0c048493          	addi	s1,s1,192
80002938:	03348863          	beq	s1,s3,80002968 <reparent+0x74>
    if(pp->parent == p){
8000293c:	0104a783          	lw	a5,16(s1)
80002940:	ff279ae3          	bne	a5,s2,80002934 <reparent+0x40>
      acquire(&pp->lock);
80002944:	00048513          	mv	a0,s1
80002948:	ffffe097          	auipc	ra,0xffffe
8000294c:	5b4080e7          	jalr	1460(ra) # 80000efc <acquire>
      pp->parent = initproc;
80002950:	000a2783          	lw	a5,0(s4)
80002954:	00f4a823          	sw	a5,16(s1)
      release(&pp->lock);
80002958:	00048513          	mv	a0,s1
8000295c:	ffffe097          	auipc	ra,0xffffe
80002960:	614080e7          	jalr	1556(ra) # 80000f70 <release>
80002964:	fd1ff06f          	j	80002934 <reparent+0x40>
}
80002968:	01c12083          	lw	ra,28(sp)
8000296c:	01812403          	lw	s0,24(sp)
80002970:	01412483          	lw	s1,20(sp)
80002974:	01012903          	lw	s2,16(sp)
80002978:	00c12983          	lw	s3,12(sp)
8000297c:	00812a03          	lw	s4,8(sp)
80002980:	02010113          	addi	sp,sp,32
80002984:	00008067          	ret

80002988 <scheduler>:
{
80002988:	fe010113          	addi	sp,sp,-32
8000298c:	00112e23          	sw	ra,28(sp)
80002990:	00812c23          	sw	s0,24(sp)
80002994:	00912a23          	sw	s1,20(sp)
80002998:	01212823          	sw	s2,16(sp)
8000299c:	01312623          	sw	s3,12(sp)
800029a0:	01412423          	sw	s4,8(sp)
800029a4:	01512223          	sw	s5,4(sp)
800029a8:	02010413          	addi	s0,sp,32
800029ac:	00020713          	mv	a4,tp
  c->proc = 0;
800029b0:	00471793          	slli	a5,a4,0x4
800029b4:	00e78633          	add	a2,a5,a4
800029b8:	00261613          	slli	a2,a2,0x2
800029bc:	00011697          	auipc	a3,0x11
800029c0:	afc68693          	addi	a3,a3,-1284 # 800134b8 <pid_lock>
800029c4:	00c686b3          	add	a3,a3,a2
800029c8:	0006a623          	sw	zero,12(a3)
        swtch(&c->scheduler, &p->context);
800029cc:	00011797          	auipc	a5,0x11
800029d0:	afc78793          	addi	a5,a5,-1284 # 800134c8 <cpus+0x4>
800029d4:	00f60ab3          	add	s5,a2,a5
      if(p->state == RUNNABLE) {
800029d8:	00200913          	li	s2,2
        c->proc = p;
800029dc:	00068993          	mv	s3,a3
  asm volatile("csrr %0, sie" : "=r" (x) );
800029e0:	104027f3          	csrr	a5,sie
  w_sie(r_sie() | SIE_SEIE | SIE_STIE | SIE_SSIE);
800029e4:	2227e793          	ori	a5,a5,546
  asm volatile("csrw sie, %0" : : "r" (x));
800029e8:	10479073          	csrw	sie,a5
  asm volatile("csrr %0, sstatus" : "=r" (x) );
800029ec:	100027f3          	csrr	a5,sstatus
  w_sstatus(r_sstatus() | SSTATUS_SIE);
800029f0:	0027e793          	ori	a5,a5,2
  asm volatile("csrw sstatus, %0" : : "r" (x));
800029f4:	10079073          	csrw	sstatus,a5
    for(p = proc; p < &proc[NPROC]; p++) {
800029f8:	00011497          	auipc	s1,0x11
800029fc:	cec48493          	addi	s1,s1,-788 # 800136e4 <proc>
        p->state = RUNNING;
80002a00:	00300a13          	li	s4,3
80002a04:	0200006f          	j	80002a24 <scheduler+0x9c>
      release(&p->lock);
80002a08:	00048513          	mv	a0,s1
80002a0c:	ffffe097          	auipc	ra,0xffffe
80002a10:	564080e7          	jalr	1380(ra) # 80000f70 <release>
    for(p = proc; p < &proc[NPROC]; p++) {
80002a14:	0c048493          	addi	s1,s1,192
80002a18:	00014797          	auipc	a5,0x14
80002a1c:	ccc78793          	addi	a5,a5,-820 # 800166e4 <tickslock>
80002a20:	fcf480e3          	beq	s1,a5,800029e0 <scheduler+0x58>
      acquire(&p->lock);
80002a24:	00048513          	mv	a0,s1
80002a28:	ffffe097          	auipc	ra,0xffffe
80002a2c:	4d4080e7          	jalr	1236(ra) # 80000efc <acquire>
      if(p->state == RUNNABLE) {
80002a30:	00c4a783          	lw	a5,12(s1)
80002a34:	fd279ae3          	bne	a5,s2,80002a08 <scheduler+0x80>
        p->state = RUNNING;
80002a38:	0144a623          	sw	s4,12(s1)
        c->proc = p;
80002a3c:	0099a623          	sw	s1,12(s3)
        swtch(&c->scheduler, &p->context);
80002a40:	03448593          	addi	a1,s1,52
80002a44:	000a8513          	mv	a0,s5
80002a48:	00001097          	auipc	ra,0x1
80002a4c:	83c080e7          	jalr	-1988(ra) # 80003284 <swtch>
        c->proc = 0;
80002a50:	0009a623          	sw	zero,12(s3)
80002a54:	fb5ff06f          	j	80002a08 <scheduler+0x80>

80002a58 <sched>:
{
80002a58:	fe010113          	addi	sp,sp,-32
80002a5c:	00112e23          	sw	ra,28(sp)
80002a60:	00812c23          	sw	s0,24(sp)
80002a64:	00912a23          	sw	s1,20(sp)
80002a68:	01212823          	sw	s2,16(sp)
80002a6c:	01312623          	sw	s3,12(sp)
80002a70:	02010413          	addi	s0,sp,32
  struct proc *p = myproc();
80002a74:	00000097          	auipc	ra,0x0
80002a78:	868080e7          	jalr	-1944(ra) # 800022dc <myproc>
80002a7c:	00050493          	mv	s1,a0
  if(!holding(&p->lock))
80002a80:	ffffe097          	auipc	ra,0xffffe
80002a84:	418080e7          	jalr	1048(ra) # 80000e98 <holding>
80002a88:	0c050063          	beqz	a0,80002b48 <sched+0xf0>
  asm volatile("mv %0, tp" : "=r" (x) );
80002a8c:	00020713          	mv	a4,tp
  if(mycpu()->noff != 1)
80002a90:	00471793          	slli	a5,a4,0x4
80002a94:	00e787b3          	add	a5,a5,a4
80002a98:	00279793          	slli	a5,a5,0x2
80002a9c:	00011717          	auipc	a4,0x11
80002aa0:	a1c70713          	addi	a4,a4,-1508 # 800134b8 <pid_lock>
80002aa4:	00f707b3          	add	a5,a4,a5
80002aa8:	0487a703          	lw	a4,72(a5)
80002aac:	00100793          	li	a5,1
80002ab0:	0af71463          	bne	a4,a5,80002b58 <sched+0x100>
  if(p->state == RUNNING)
80002ab4:	00c4a703          	lw	a4,12(s1)
80002ab8:	00300793          	li	a5,3
80002abc:	0af70663          	beq	a4,a5,80002b68 <sched+0x110>
  asm volatile("csrr %0, sstatus" : "=r" (x) );
80002ac0:	100027f3          	csrr	a5,sstatus
  return (x & SSTATUS_SIE) != 0;
80002ac4:	0027f793          	andi	a5,a5,2
  if(intr_get())
80002ac8:	0a079863          	bnez	a5,80002b78 <sched+0x120>
  asm volatile("mv %0, tp" : "=r" (x) );
80002acc:	00020713          	mv	a4,tp
  intena = mycpu()->intena;
80002ad0:	00011917          	auipc	s2,0x11
80002ad4:	9e890913          	addi	s2,s2,-1560 # 800134b8 <pid_lock>
80002ad8:	00471793          	slli	a5,a4,0x4
80002adc:	00e787b3          	add	a5,a5,a4
80002ae0:	00279793          	slli	a5,a5,0x2
80002ae4:	00f907b3          	add	a5,s2,a5
80002ae8:	04c7a983          	lw	s3,76(a5)
80002aec:	00020713          	mv	a4,tp
  swtch(&p->context, &mycpu()->scheduler);
80002af0:	00471793          	slli	a5,a4,0x4
80002af4:	00e787b3          	add	a5,a5,a4
80002af8:	00279793          	slli	a5,a5,0x2
80002afc:	00011597          	auipc	a1,0x11
80002b00:	9cc58593          	addi	a1,a1,-1588 # 800134c8 <cpus+0x4>
80002b04:	00b785b3          	add	a1,a5,a1
80002b08:	03448513          	addi	a0,s1,52
80002b0c:	00000097          	auipc	ra,0x0
80002b10:	778080e7          	jalr	1912(ra) # 80003284 <swtch>
80002b14:	00020713          	mv	a4,tp
  mycpu()->intena = intena;
80002b18:	00471793          	slli	a5,a4,0x4
80002b1c:	00e787b3          	add	a5,a5,a4
80002b20:	00279793          	slli	a5,a5,0x2
80002b24:	00f90933          	add	s2,s2,a5
80002b28:	05392623          	sw	s3,76(s2)
}
80002b2c:	01c12083          	lw	ra,28(sp)
80002b30:	01812403          	lw	s0,24(sp)
80002b34:	01412483          	lw	s1,20(sp)
80002b38:	01012903          	lw	s2,16(sp)
80002b3c:	00c12983          	lw	s3,12(sp)
80002b40:	02010113          	addi	sp,sp,32
80002b44:	00008067          	ret
    panic("sched p->lock");
80002b48:	00006517          	auipc	a0,0x6
80002b4c:	7bc50513          	addi	a0,a0,1980 # 80009304 <userret+0x264>
80002b50:	ffffe097          	auipc	ra,0xffffe
80002b54:	bac080e7          	jalr	-1108(ra) # 800006fc <panic>
    panic("sched locks");
80002b58:	00006517          	auipc	a0,0x6
80002b5c:	7bc50513          	addi	a0,a0,1980 # 80009314 <userret+0x274>
80002b60:	ffffe097          	auipc	ra,0xffffe
80002b64:	b9c080e7          	jalr	-1124(ra) # 800006fc <panic>
    panic("sched running");
80002b68:	00006517          	auipc	a0,0x6
80002b6c:	7b850513          	addi	a0,a0,1976 # 80009320 <userret+0x280>
80002b70:	ffffe097          	auipc	ra,0xffffe
80002b74:	b8c080e7          	jalr	-1140(ra) # 800006fc <panic>
    panic("sched interruptible");
80002b78:	00006517          	auipc	a0,0x6
80002b7c:	7b850513          	addi	a0,a0,1976 # 80009330 <userret+0x290>
80002b80:	ffffe097          	auipc	ra,0xffffe
80002b84:	b7c080e7          	jalr	-1156(ra) # 800006fc <panic>

80002b88 <exit>:
{
80002b88:	fe010113          	addi	sp,sp,-32
80002b8c:	00112e23          	sw	ra,28(sp)
80002b90:	00812c23          	sw	s0,24(sp)
80002b94:	00912a23          	sw	s1,20(sp)
80002b98:	01212823          	sw	s2,16(sp)
80002b9c:	01312623          	sw	s3,12(sp)
80002ba0:	01412423          	sw	s4,8(sp)
80002ba4:	02010413          	addi	s0,sp,32
80002ba8:	00050a13          	mv	s4,a0
  struct proc *p = myproc();
80002bac:	fffff097          	auipc	ra,0xfffff
80002bb0:	730080e7          	jalr	1840(ra) # 800022dc <myproc>
80002bb4:	00050993          	mv	s3,a0
  if(p == initproc)
80002bb8:	00021797          	auipc	a5,0x21
80002bbc:	4547a783          	lw	a5,1108(a5) # 8002400c <initproc>
80002bc0:	06c50493          	addi	s1,a0,108
80002bc4:	0ac50913          	addi	s2,a0,172
80002bc8:	00a79e63          	bne	a5,a0,80002be4 <exit+0x5c>
    panic("init exiting");
80002bcc:	00006517          	auipc	a0,0x6
80002bd0:	77850513          	addi	a0,a0,1912 # 80009344 <userret+0x2a4>
80002bd4:	ffffe097          	auipc	ra,0xffffe
80002bd8:	b28080e7          	jalr	-1240(ra) # 800006fc <panic>
  for(int fd = 0; fd < NOFILE; fd++){
80002bdc:	00448493          	addi	s1,s1,4
80002be0:	01248e63          	beq	s1,s2,80002bfc <exit+0x74>
    if(p->ofile[fd]){
80002be4:	0004a503          	lw	a0,0(s1)
80002be8:	fe050ae3          	beqz	a0,80002bdc <exit+0x54>
      fileclose(f);
80002bec:	00003097          	auipc	ra,0x3
80002bf0:	128080e7          	jalr	296(ra) # 80005d14 <fileclose>
      p->ofile[fd] = 0;
80002bf4:	0004a023          	sw	zero,0(s1)
80002bf8:	fe5ff06f          	j	80002bdc <exit+0x54>
  begin_op();
80002bfc:	00003097          	auipc	ra,0x3
80002c00:	a7c080e7          	jalr	-1412(ra) # 80005678 <begin_op>
  iput(p->cwd);
80002c04:	0ac9a503          	lw	a0,172(s3)
80002c08:	00002097          	auipc	ra,0x2
80002c0c:	e2c080e7          	jalr	-468(ra) # 80004a34 <iput>
  end_op();
80002c10:	00003097          	auipc	ra,0x3
80002c14:	b1c080e7          	jalr	-1252(ra) # 8000572c <end_op>
  p->cwd = 0;
80002c18:	0a09a623          	sw	zero,172(s3)
  acquire(&initproc->lock);
80002c1c:	00021497          	auipc	s1,0x21
80002c20:	3f048493          	addi	s1,s1,1008 # 8002400c <initproc>
80002c24:	0004a503          	lw	a0,0(s1)
80002c28:	ffffe097          	auipc	ra,0xffffe
80002c2c:	2d4080e7          	jalr	724(ra) # 80000efc <acquire>
  wakeup1(initproc);
80002c30:	0004a503          	lw	a0,0(s1)
80002c34:	fffff097          	auipc	ra,0xfffff
80002c38:	4c0080e7          	jalr	1216(ra) # 800020f4 <wakeup1>
  release(&initproc->lock);
80002c3c:	0004a503          	lw	a0,0(s1)
80002c40:	ffffe097          	auipc	ra,0xffffe
80002c44:	330080e7          	jalr	816(ra) # 80000f70 <release>
  acquire(&p->lock);
80002c48:	00098513          	mv	a0,s3
80002c4c:	ffffe097          	auipc	ra,0xffffe
80002c50:	2b0080e7          	jalr	688(ra) # 80000efc <acquire>
  struct proc *original_parent = p->parent;
80002c54:	0109a483          	lw	s1,16(s3)
  release(&p->lock);
80002c58:	00098513          	mv	a0,s3
80002c5c:	ffffe097          	auipc	ra,0xffffe
80002c60:	314080e7          	jalr	788(ra) # 80000f70 <release>
  acquire(&original_parent->lock);
80002c64:	00048513          	mv	a0,s1
80002c68:	ffffe097          	auipc	ra,0xffffe
80002c6c:	294080e7          	jalr	660(ra) # 80000efc <acquire>
  acquire(&p->lock);
80002c70:	00098513          	mv	a0,s3
80002c74:	ffffe097          	auipc	ra,0xffffe
80002c78:	288080e7          	jalr	648(ra) # 80000efc <acquire>
  reparent(p);
80002c7c:	00098513          	mv	a0,s3
80002c80:	00000097          	auipc	ra,0x0
80002c84:	c74080e7          	jalr	-908(ra) # 800028f4 <reparent>
  wakeup1(original_parent);
80002c88:	00048513          	mv	a0,s1
80002c8c:	fffff097          	auipc	ra,0xfffff
80002c90:	468080e7          	jalr	1128(ra) # 800020f4 <wakeup1>
  p->xstate = status;
80002c94:	0149ae23          	sw	s4,28(s3)
  p->state = ZOMBIE;
80002c98:	00400793          	li	a5,4
80002c9c:	00f9a623          	sw	a5,12(s3)
  release(&original_parent->lock);
80002ca0:	00048513          	mv	a0,s1
80002ca4:	ffffe097          	auipc	ra,0xffffe
80002ca8:	2cc080e7          	jalr	716(ra) # 80000f70 <release>
  sched();
80002cac:	00000097          	auipc	ra,0x0
80002cb0:	dac080e7          	jalr	-596(ra) # 80002a58 <sched>
  panic("zombie exit");
80002cb4:	00006517          	auipc	a0,0x6
80002cb8:	6a050513          	addi	a0,a0,1696 # 80009354 <userret+0x2b4>
80002cbc:	ffffe097          	auipc	ra,0xffffe
80002cc0:	a40080e7          	jalr	-1472(ra) # 800006fc <panic>

80002cc4 <yield>:
{
80002cc4:	ff010113          	addi	sp,sp,-16
80002cc8:	00112623          	sw	ra,12(sp)
80002ccc:	00812423          	sw	s0,8(sp)
80002cd0:	00912223          	sw	s1,4(sp)
80002cd4:	01010413          	addi	s0,sp,16
  struct proc *p = myproc();
80002cd8:	fffff097          	auipc	ra,0xfffff
80002cdc:	604080e7          	jalr	1540(ra) # 800022dc <myproc>
80002ce0:	00050493          	mv	s1,a0
  acquire(&p->lock);
80002ce4:	ffffe097          	auipc	ra,0xffffe
80002ce8:	218080e7          	jalr	536(ra) # 80000efc <acquire>
  p->state = RUNNABLE;
80002cec:	00200793          	li	a5,2
80002cf0:	00f4a623          	sw	a5,12(s1)
  sched();
80002cf4:	00000097          	auipc	ra,0x0
80002cf8:	d64080e7          	jalr	-668(ra) # 80002a58 <sched>
  release(&p->lock);
80002cfc:	00048513          	mv	a0,s1
80002d00:	ffffe097          	auipc	ra,0xffffe
80002d04:	270080e7          	jalr	624(ra) # 80000f70 <release>
}
80002d08:	00c12083          	lw	ra,12(sp)
80002d0c:	00812403          	lw	s0,8(sp)
80002d10:	00412483          	lw	s1,4(sp)
80002d14:	01010113          	addi	sp,sp,16
80002d18:	00008067          	ret

80002d1c <sleep>:
{
80002d1c:	fe010113          	addi	sp,sp,-32
80002d20:	00112e23          	sw	ra,28(sp)
80002d24:	00812c23          	sw	s0,24(sp)
80002d28:	00912a23          	sw	s1,20(sp)
80002d2c:	01212823          	sw	s2,16(sp)
80002d30:	01312623          	sw	s3,12(sp)
80002d34:	02010413          	addi	s0,sp,32
80002d38:	00050993          	mv	s3,a0
80002d3c:	00058913          	mv	s2,a1
  struct proc *p = myproc();
80002d40:	fffff097          	auipc	ra,0xfffff
80002d44:	59c080e7          	jalr	1436(ra) # 800022dc <myproc>
80002d48:	00050493          	mv	s1,a0
  if(lk != &p->lock){  //DOC: sleeplock0
80002d4c:	07250263          	beq	a0,s2,80002db0 <sleep+0x94>
    acquire(&p->lock);  //DOC: sleeplock1
80002d50:	ffffe097          	auipc	ra,0xffffe
80002d54:	1ac080e7          	jalr	428(ra) # 80000efc <acquire>
    release(lk);
80002d58:	00090513          	mv	a0,s2
80002d5c:	ffffe097          	auipc	ra,0xffffe
80002d60:	214080e7          	jalr	532(ra) # 80000f70 <release>
  p->chan = chan;
80002d64:	0134aa23          	sw	s3,20(s1)
  p->state = SLEEPING;
80002d68:	00100793          	li	a5,1
80002d6c:	00f4a623          	sw	a5,12(s1)
  sched();
80002d70:	00000097          	auipc	ra,0x0
80002d74:	ce8080e7          	jalr	-792(ra) # 80002a58 <sched>
  p->chan = 0;
80002d78:	0004aa23          	sw	zero,20(s1)
    release(&p->lock);
80002d7c:	00048513          	mv	a0,s1
80002d80:	ffffe097          	auipc	ra,0xffffe
80002d84:	1f0080e7          	jalr	496(ra) # 80000f70 <release>
    acquire(lk);
80002d88:	00090513          	mv	a0,s2
80002d8c:	ffffe097          	auipc	ra,0xffffe
80002d90:	170080e7          	jalr	368(ra) # 80000efc <acquire>
}
80002d94:	01c12083          	lw	ra,28(sp)
80002d98:	01812403          	lw	s0,24(sp)
80002d9c:	01412483          	lw	s1,20(sp)
80002da0:	01012903          	lw	s2,16(sp)
80002da4:	00c12983          	lw	s3,12(sp)
80002da8:	02010113          	addi	sp,sp,32
80002dac:	00008067          	ret
  p->chan = chan;
80002db0:	0134aa23          	sw	s3,20(s1)
  p->state = SLEEPING;
80002db4:	00100793          	li	a5,1
80002db8:	00f52623          	sw	a5,12(a0)
  sched();
80002dbc:	00000097          	auipc	ra,0x0
80002dc0:	c9c080e7          	jalr	-868(ra) # 80002a58 <sched>
  p->chan = 0;
80002dc4:	0004aa23          	sw	zero,20(s1)
  if(lk != &p->lock){
80002dc8:	fcdff06f          	j	80002d94 <sleep+0x78>

80002dcc <wait>:
{
80002dcc:	fe010113          	addi	sp,sp,-32
80002dd0:	00112e23          	sw	ra,28(sp)
80002dd4:	00812c23          	sw	s0,24(sp)
80002dd8:	00912a23          	sw	s1,20(sp)
80002ddc:	01212823          	sw	s2,16(sp)
80002de0:	01312623          	sw	s3,12(sp)
80002de4:	01412423          	sw	s4,8(sp)
80002de8:	01512223          	sw	s5,4(sp)
80002dec:	01612023          	sw	s6,0(sp)
80002df0:	02010413          	addi	s0,sp,32
80002df4:	00050b13          	mv	s6,a0
  struct proc *p = myproc();
80002df8:	fffff097          	auipc	ra,0xfffff
80002dfc:	4e4080e7          	jalr	1252(ra) # 800022dc <myproc>
80002e00:	00050913          	mv	s2,a0
  acquire(&p->lock);
80002e04:	ffffe097          	auipc	ra,0xffffe
80002e08:	0f8080e7          	jalr	248(ra) # 80000efc <acquire>
        if(np->state == ZOMBIE){
80002e0c:	00400a13          	li	s4,4
        havekids = 1;
80002e10:	00100a93          	li	s5,1
    for(np = proc; np < &proc[NPROC]; np++){
80002e14:	00014997          	auipc	s3,0x14
80002e18:	8d098993          	addi	s3,s3,-1840 # 800166e4 <tickslock>
80002e1c:	0ec0006f          	j	80002f08 <wait+0x13c>
          pid = np->pid;
80002e20:	0204a983          	lw	s3,32(s1)
          if(addr != 0 && copyout(p->pagetable, addr, (char *)&np->xstate,
80002e24:	020b0063          	beqz	s6,80002e44 <wait+0x78>
80002e28:	00400693          	li	a3,4
80002e2c:	01c48613          	addi	a2,s1,28
80002e30:	000b0593          	mv	a1,s6
80002e34:	02c92503          	lw	a0,44(s2)
80002e38:	fffff097          	auipc	ra,0xfffff
80002e3c:	fc4080e7          	jalr	-60(ra) # 80001dfc <copyout>
80002e40:	04054a63          	bltz	a0,80002e94 <wait+0xc8>
          freeproc(np);
80002e44:	00048513          	mv	a0,s1
80002e48:	fffff097          	auipc	ra,0xfffff
80002e4c:	790080e7          	jalr	1936(ra) # 800025d8 <freeproc>
          release(&np->lock);
80002e50:	00048513          	mv	a0,s1
80002e54:	ffffe097          	auipc	ra,0xffffe
80002e58:	11c080e7          	jalr	284(ra) # 80000f70 <release>
          release(&p->lock);
80002e5c:	00090513          	mv	a0,s2
80002e60:	ffffe097          	auipc	ra,0xffffe
80002e64:	110080e7          	jalr	272(ra) # 80000f70 <release>
}
80002e68:	00098513          	mv	a0,s3
80002e6c:	01c12083          	lw	ra,28(sp)
80002e70:	01812403          	lw	s0,24(sp)
80002e74:	01412483          	lw	s1,20(sp)
80002e78:	01012903          	lw	s2,16(sp)
80002e7c:	00c12983          	lw	s3,12(sp)
80002e80:	00812a03          	lw	s4,8(sp)
80002e84:	00412a83          	lw	s5,4(sp)
80002e88:	00012b03          	lw	s6,0(sp)
80002e8c:	02010113          	addi	sp,sp,32
80002e90:	00008067          	ret
            release(&np->lock);
80002e94:	00048513          	mv	a0,s1
80002e98:	ffffe097          	auipc	ra,0xffffe
80002e9c:	0d8080e7          	jalr	216(ra) # 80000f70 <release>
            release(&p->lock);
80002ea0:	00090513          	mv	a0,s2
80002ea4:	ffffe097          	auipc	ra,0xffffe
80002ea8:	0cc080e7          	jalr	204(ra) # 80000f70 <release>
            return -1;
80002eac:	fff00993          	li	s3,-1
80002eb0:	fb9ff06f          	j	80002e68 <wait+0x9c>
    for(np = proc; np < &proc[NPROC]; np++){
80002eb4:	0c048493          	addi	s1,s1,192
80002eb8:	03348a63          	beq	s1,s3,80002eec <wait+0x120>
      if(np->parent == p){
80002ebc:	0104a783          	lw	a5,16(s1)
80002ec0:	ff279ae3          	bne	a5,s2,80002eb4 <wait+0xe8>
        acquire(&np->lock);
80002ec4:	00048513          	mv	a0,s1
80002ec8:	ffffe097          	auipc	ra,0xffffe
80002ecc:	034080e7          	jalr	52(ra) # 80000efc <acquire>
        if(np->state == ZOMBIE){
80002ed0:	00c4a783          	lw	a5,12(s1)
80002ed4:	f54786e3          	beq	a5,s4,80002e20 <wait+0x54>
        release(&np->lock);
80002ed8:	00048513          	mv	a0,s1
80002edc:	ffffe097          	auipc	ra,0xffffe
80002ee0:	094080e7          	jalr	148(ra) # 80000f70 <release>
        havekids = 1;
80002ee4:	000a8713          	mv	a4,s5
80002ee8:	fcdff06f          	j	80002eb4 <wait+0xe8>
    if(!havekids || p->killed){
80002eec:	02070663          	beqz	a4,80002f18 <wait+0x14c>
80002ef0:	01892783          	lw	a5,24(s2)
80002ef4:	02079263          	bnez	a5,80002f18 <wait+0x14c>
    sleep(p, &p->lock);  //DOC: wait-sleep
80002ef8:	00090593          	mv	a1,s2
80002efc:	00090513          	mv	a0,s2
80002f00:	00000097          	auipc	ra,0x0
80002f04:	e1c080e7          	jalr	-484(ra) # 80002d1c <sleep>
    havekids = 0;
80002f08:	00000713          	li	a4,0
    for(np = proc; np < &proc[NPROC]; np++){
80002f0c:	00010497          	auipc	s1,0x10
80002f10:	7d848493          	addi	s1,s1,2008 # 800136e4 <proc>
80002f14:	fa9ff06f          	j	80002ebc <wait+0xf0>
      release(&p->lock);
80002f18:	00090513          	mv	a0,s2
80002f1c:	ffffe097          	auipc	ra,0xffffe
80002f20:	054080e7          	jalr	84(ra) # 80000f70 <release>
      return -1;
80002f24:	fff00993          	li	s3,-1
80002f28:	f41ff06f          	j	80002e68 <wait+0x9c>

80002f2c <wakeup>:
{
80002f2c:	fe010113          	addi	sp,sp,-32
80002f30:	00112e23          	sw	ra,28(sp)
80002f34:	00812c23          	sw	s0,24(sp)
80002f38:	00912a23          	sw	s1,20(sp)
80002f3c:	01212823          	sw	s2,16(sp)
80002f40:	01312623          	sw	s3,12(sp)
80002f44:	01412423          	sw	s4,8(sp)
80002f48:	01512223          	sw	s5,4(sp)
80002f4c:	02010413          	addi	s0,sp,32
80002f50:	00050a13          	mv	s4,a0
  for(p = proc; p < &proc[NPROC]; p++) {
80002f54:	00010497          	auipc	s1,0x10
80002f58:	79048493          	addi	s1,s1,1936 # 800136e4 <proc>
    if(p->state == SLEEPING && p->chan == chan) {
80002f5c:	00100993          	li	s3,1
      p->state = RUNNABLE;
80002f60:	00200a93          	li	s5,2
  for(p = proc; p < &proc[NPROC]; p++) {
80002f64:	00013917          	auipc	s2,0x13
80002f68:	78090913          	addi	s2,s2,1920 # 800166e4 <tickslock>
80002f6c:	0180006f          	j	80002f84 <wakeup+0x58>
    release(&p->lock);
80002f70:	00048513          	mv	a0,s1
80002f74:	ffffe097          	auipc	ra,0xffffe
80002f78:	ffc080e7          	jalr	-4(ra) # 80000f70 <release>
  for(p = proc; p < &proc[NPROC]; p++) {
80002f7c:	0c048493          	addi	s1,s1,192
80002f80:	03248463          	beq	s1,s2,80002fa8 <wakeup+0x7c>
    acquire(&p->lock);
80002f84:	00048513          	mv	a0,s1
80002f88:	ffffe097          	auipc	ra,0xffffe
80002f8c:	f74080e7          	jalr	-140(ra) # 80000efc <acquire>
    if(p->state == SLEEPING && p->chan == chan) {
80002f90:	00c4a783          	lw	a5,12(s1)
80002f94:	fd379ee3          	bne	a5,s3,80002f70 <wakeup+0x44>
80002f98:	0144a783          	lw	a5,20(s1)
80002f9c:	fd479ae3          	bne	a5,s4,80002f70 <wakeup+0x44>
      p->state = RUNNABLE;
80002fa0:	0154a623          	sw	s5,12(s1)
80002fa4:	fcdff06f          	j	80002f70 <wakeup+0x44>
}
80002fa8:	01c12083          	lw	ra,28(sp)
80002fac:	01812403          	lw	s0,24(sp)
80002fb0:	01412483          	lw	s1,20(sp)
80002fb4:	01012903          	lw	s2,16(sp)
80002fb8:	00c12983          	lw	s3,12(sp)
80002fbc:	00812a03          	lw	s4,8(sp)
80002fc0:	00412a83          	lw	s5,4(sp)
80002fc4:	02010113          	addi	sp,sp,32
80002fc8:	00008067          	ret

80002fcc <kill>:
// Kill the process with the given pid.
// The victim won't exit until it tries to return
// to user space (see usertrap() in trap.c).
int
kill(int pid)
{
80002fcc:	fe010113          	addi	sp,sp,-32
80002fd0:	00112e23          	sw	ra,28(sp)
80002fd4:	00812c23          	sw	s0,24(sp)
80002fd8:	00912a23          	sw	s1,20(sp)
80002fdc:	01212823          	sw	s2,16(sp)
80002fe0:	01312623          	sw	s3,12(sp)
80002fe4:	02010413          	addi	s0,sp,32
80002fe8:	00050913          	mv	s2,a0
  struct proc *p;

  for(p = proc; p < &proc[NPROC]; p++){
80002fec:	00010497          	auipc	s1,0x10
80002ff0:	6f848493          	addi	s1,s1,1784 # 800136e4 <proc>
80002ff4:	00013997          	auipc	s3,0x13
80002ff8:	6f098993          	addi	s3,s3,1776 # 800166e4 <tickslock>
    acquire(&p->lock);
80002ffc:	00048513          	mv	a0,s1
80003000:	ffffe097          	auipc	ra,0xffffe
80003004:	efc080e7          	jalr	-260(ra) # 80000efc <acquire>
    if(p->pid == pid){
80003008:	0204a783          	lw	a5,32(s1)
8000300c:	03278063          	beq	a5,s2,8000302c <kill+0x60>
        p->state = RUNNABLE;
      }
      release(&p->lock);
      return 0;
    }
    release(&p->lock);
80003010:	00048513          	mv	a0,s1
80003014:	ffffe097          	auipc	ra,0xffffe
80003018:	f5c080e7          	jalr	-164(ra) # 80000f70 <release>
  for(p = proc; p < &proc[NPROC]; p++){
8000301c:	0c048493          	addi	s1,s1,192
80003020:	fd349ee3          	bne	s1,s3,80002ffc <kill+0x30>
  }
  return -1;
80003024:	fff00513          	li	a0,-1
80003028:	0240006f          	j	8000304c <kill+0x80>
      p->killed = 1;
8000302c:	00100793          	li	a5,1
80003030:	00f4ac23          	sw	a5,24(s1)
      if(p->state == SLEEPING){
80003034:	00c4a703          	lw	a4,12(s1)
80003038:	02f70863          	beq	a4,a5,80003068 <kill+0x9c>
      release(&p->lock);
8000303c:	00048513          	mv	a0,s1
80003040:	ffffe097          	auipc	ra,0xffffe
80003044:	f30080e7          	jalr	-208(ra) # 80000f70 <release>
      return 0;
80003048:	00000513          	li	a0,0
}
8000304c:	01c12083          	lw	ra,28(sp)
80003050:	01812403          	lw	s0,24(sp)
80003054:	01412483          	lw	s1,20(sp)
80003058:	01012903          	lw	s2,16(sp)
8000305c:	00c12983          	lw	s3,12(sp)
80003060:	02010113          	addi	sp,sp,32
80003064:	00008067          	ret
        p->state = RUNNABLE;
80003068:	00200793          	li	a5,2
8000306c:	00f4a623          	sw	a5,12(s1)
80003070:	fcdff06f          	j	8000303c <kill+0x70>

80003074 <either_copyout>:
// Copy to either a user address, or kernel address,
// depending on usr_dst.
// Returns 0 on success, -1 on error.
int
either_copyout(int user_dst, uint32 dst, void *src, uint32 len)
{
80003074:	fe010113          	addi	sp,sp,-32
80003078:	00112e23          	sw	ra,28(sp)
8000307c:	00812c23          	sw	s0,24(sp)
80003080:	00912a23          	sw	s1,20(sp)
80003084:	01212823          	sw	s2,16(sp)
80003088:	01312623          	sw	s3,12(sp)
8000308c:	01412423          	sw	s4,8(sp)
80003090:	02010413          	addi	s0,sp,32
80003094:	00050493          	mv	s1,a0
80003098:	00058a13          	mv	s4,a1
8000309c:	00060993          	mv	s3,a2
800030a0:	00068913          	mv	s2,a3
  struct proc *p = myproc();
800030a4:	fffff097          	auipc	ra,0xfffff
800030a8:	238080e7          	jalr	568(ra) # 800022dc <myproc>
  if(user_dst){
800030ac:	02048e63          	beqz	s1,800030e8 <either_copyout+0x74>
    return copyout(p->pagetable, dst, src, len);
800030b0:	00090693          	mv	a3,s2
800030b4:	00098613          	mv	a2,s3
800030b8:	000a0593          	mv	a1,s4
800030bc:	02c52503          	lw	a0,44(a0)
800030c0:	fffff097          	auipc	ra,0xfffff
800030c4:	d3c080e7          	jalr	-708(ra) # 80001dfc <copyout>
  } else {
    memmove((char *)dst, src, len);
    return 0;
  }
}
800030c8:	01c12083          	lw	ra,28(sp)
800030cc:	01812403          	lw	s0,24(sp)
800030d0:	01412483          	lw	s1,20(sp)
800030d4:	01012903          	lw	s2,16(sp)
800030d8:	00c12983          	lw	s3,12(sp)
800030dc:	00812a03          	lw	s4,8(sp)
800030e0:	02010113          	addi	sp,sp,32
800030e4:	00008067          	ret
    memmove((char *)dst, src, len);
800030e8:	00090613          	mv	a2,s2
800030ec:	00098593          	mv	a1,s3
800030f0:	000a0513          	mv	a0,s4
800030f4:	ffffe097          	auipc	ra,0xffffe
800030f8:	f68080e7          	jalr	-152(ra) # 8000105c <memmove>
    return 0;
800030fc:	00048513          	mv	a0,s1
80003100:	fc9ff06f          	j	800030c8 <either_copyout+0x54>

80003104 <either_copyin>:
// Copy from either a user address, or kernel address,
// depending on usr_src.
// Returns 0 on success, -1 on error.
int
either_copyin(void *dst, int user_src, uint32 src, uint32 len)
{
80003104:	fe010113          	addi	sp,sp,-32
80003108:	00112e23          	sw	ra,28(sp)
8000310c:	00812c23          	sw	s0,24(sp)
80003110:	00912a23          	sw	s1,20(sp)
80003114:	01212823          	sw	s2,16(sp)
80003118:	01312623          	sw	s3,12(sp)
8000311c:	01412423          	sw	s4,8(sp)
80003120:	02010413          	addi	s0,sp,32
80003124:	00050a13          	mv	s4,a0
80003128:	00058493          	mv	s1,a1
8000312c:	00060993          	mv	s3,a2
80003130:	00068913          	mv	s2,a3
  struct proc *p = myproc();
80003134:	fffff097          	auipc	ra,0xfffff
80003138:	1a8080e7          	jalr	424(ra) # 800022dc <myproc>
  if(user_src){
8000313c:	02048e63          	beqz	s1,80003178 <either_copyin+0x74>
    return copyin(p->pagetable, dst, src, len);
80003140:	00090693          	mv	a3,s2
80003144:	00098613          	mv	a2,s3
80003148:	000a0593          	mv	a1,s4
8000314c:	02c52503          	lw	a0,44(a0)
80003150:	fffff097          	auipc	ra,0xfffff
80003154:	d94080e7          	jalr	-620(ra) # 80001ee4 <copyin>
  } else {
    memmove(dst, (char*)src, len);
    return 0;
  }
}
80003158:	01c12083          	lw	ra,28(sp)
8000315c:	01812403          	lw	s0,24(sp)
80003160:	01412483          	lw	s1,20(sp)
80003164:	01012903          	lw	s2,16(sp)
80003168:	00c12983          	lw	s3,12(sp)
8000316c:	00812a03          	lw	s4,8(sp)
80003170:	02010113          	addi	sp,sp,32
80003174:	00008067          	ret
    memmove(dst, (char*)src, len);
80003178:	00090613          	mv	a2,s2
8000317c:	00098593          	mv	a1,s3
80003180:	000a0513          	mv	a0,s4
80003184:	ffffe097          	auipc	ra,0xffffe
80003188:	ed8080e7          	jalr	-296(ra) # 8000105c <memmove>
    return 0;
8000318c:	00048513          	mv	a0,s1
80003190:	fc9ff06f          	j	80003158 <either_copyin+0x54>

80003194 <procdump>:
// Print a process listing to console.  For debugging.
// Runs when user types ^P on console.
// No lock to avoid wedging a stuck machine further.
void
procdump(void)
{
80003194:	fd010113          	addi	sp,sp,-48
80003198:	02112623          	sw	ra,44(sp)
8000319c:	02812423          	sw	s0,40(sp)
800031a0:	02912223          	sw	s1,36(sp)
800031a4:	03212023          	sw	s2,32(sp)
800031a8:	01312e23          	sw	s3,28(sp)
800031ac:	01412c23          	sw	s4,24(sp)
800031b0:	01512a23          	sw	s5,20(sp)
800031b4:	01612823          	sw	s6,16(sp)
800031b8:	01712623          	sw	s7,12(sp)
800031bc:	03010413          	addi	s0,sp,48
  [ZOMBIE]    "zombie"
  };
  struct proc *p;
  char *state;

  printf("\n");
800031c0:	00006517          	auipc	a0,0x6
800031c4:	f8050513          	addi	a0,a0,-128 # 80009140 <userret+0xa0>
800031c8:	ffffd097          	auipc	ra,0xffffd
800031cc:	590080e7          	jalr	1424(ra) # 80000758 <printf>
  for(p = proc; p < &proc[NPROC]; p++){
800031d0:	00010497          	auipc	s1,0x10
800031d4:	5c448493          	addi	s1,s1,1476 # 80013794 <proc+0xb0>
800031d8:	00013917          	auipc	s2,0x13
800031dc:	5bc90913          	addi	s2,s2,1468 # 80016794 <bcache+0xa4>
    if(p->state == UNUSED)
      continue;
    if(p->state >= 0 && p->state < NELEM(states) && states[p->state])
800031e0:	00400b13          	li	s6,4
      state = states[p->state];
    else
      state = "???";
800031e4:	00006997          	auipc	s3,0x6
800031e8:	17c98993          	addi	s3,s3,380 # 80009360 <userret+0x2c0>
    printf("%d %s %s", p->pid, state, p->name);
800031ec:	00006a97          	auipc	s5,0x6
800031f0:	178a8a93          	addi	s5,s5,376 # 80009364 <userret+0x2c4>
    printf("\n");
800031f4:	00006a17          	auipc	s4,0x6
800031f8:	f4ca0a13          	addi	s4,s4,-180 # 80009140 <userret+0xa0>
    if(p->state >= 0 && p->state < NELEM(states) && states[p->state])
800031fc:	00006b97          	auipc	s7,0x6
80003200:	604b8b93          	addi	s7,s7,1540 # 80009800 <states.0>
80003204:	0280006f          	j	8000322c <procdump+0x98>
    printf("%d %s %s", p->pid, state, p->name);
80003208:	f706a583          	lw	a1,-144(a3)
8000320c:	000a8513          	mv	a0,s5
80003210:	ffffd097          	auipc	ra,0xffffd
80003214:	548080e7          	jalr	1352(ra) # 80000758 <printf>
    printf("\n");
80003218:	000a0513          	mv	a0,s4
8000321c:	ffffd097          	auipc	ra,0xffffd
80003220:	53c080e7          	jalr	1340(ra) # 80000758 <printf>
  for(p = proc; p < &proc[NPROC]; p++){
80003224:	0c048493          	addi	s1,s1,192
80003228:	03248863          	beq	s1,s2,80003258 <procdump+0xc4>
    if(p->state == UNUSED)
8000322c:	00048693          	mv	a3,s1
80003230:	f5c4a783          	lw	a5,-164(s1)
80003234:	fe0788e3          	beqz	a5,80003224 <procdump+0x90>
      state = "???";
80003238:	00098613          	mv	a2,s3
    if(p->state >= 0 && p->state < NELEM(states) && states[p->state])
8000323c:	fcfb66e3          	bltu	s6,a5,80003208 <procdump+0x74>
80003240:	00279793          	slli	a5,a5,0x2
80003244:	00fb87b3          	add	a5,s7,a5
80003248:	0007a603          	lw	a2,0(a5)
8000324c:	fa061ee3          	bnez	a2,80003208 <procdump+0x74>
      state = "???";
80003250:	00098613          	mv	a2,s3
80003254:	fb5ff06f          	j	80003208 <procdump+0x74>
  }
}
80003258:	02c12083          	lw	ra,44(sp)
8000325c:	02812403          	lw	s0,40(sp)
80003260:	02412483          	lw	s1,36(sp)
80003264:	02012903          	lw	s2,32(sp)
80003268:	01c12983          	lw	s3,28(sp)
8000326c:	01812a03          	lw	s4,24(sp)
80003270:	01412a83          	lw	s5,20(sp)
80003274:	01012b03          	lw	s6,16(sp)
80003278:	00c12b83          	lw	s7,12(sp)
8000327c:	03010113          	addi	sp,sp,48
80003280:	00008067          	ret

80003284 <swtch>:
80003284:	00152023          	sw	ra,0(a0)
80003288:	00252223          	sw	sp,4(a0)
8000328c:	00852423          	sw	s0,8(a0)
80003290:	00952623          	sw	s1,12(a0)
80003294:	01252823          	sw	s2,16(a0)
80003298:	01352a23          	sw	s3,20(a0)
8000329c:	01452c23          	sw	s4,24(a0)
800032a0:	01552e23          	sw	s5,28(a0)
800032a4:	03652023          	sw	s6,32(a0)
800032a8:	03752223          	sw	s7,36(a0)
800032ac:	03852423          	sw	s8,40(a0)
800032b0:	03952623          	sw	s9,44(a0)
800032b4:	03a52823          	sw	s10,48(a0)
800032b8:	03b52a23          	sw	s11,52(a0)
800032bc:	0005a083          	lw	ra,0(a1)
800032c0:	0045a103          	lw	sp,4(a1)
800032c4:	0085a403          	lw	s0,8(a1)
800032c8:	00c5a483          	lw	s1,12(a1)
800032cc:	0105a903          	lw	s2,16(a1)
800032d0:	0145a983          	lw	s3,20(a1)
800032d4:	0185aa03          	lw	s4,24(a1)
800032d8:	01c5aa83          	lw	s5,28(a1)
800032dc:	0205ab03          	lw	s6,32(a1)
800032e0:	0245ab83          	lw	s7,36(a1)
800032e4:	0285ac03          	lw	s8,40(a1)
800032e8:	02c5ac83          	lw	s9,44(a1)
800032ec:	0305ad03          	lw	s10,48(a1)
800032f0:	0345ad83          	lw	s11,52(a1)
800032f4:	00008067          	ret

800032f8 <trapinit>:

extern int devintr();

void
trapinit(void)
{
800032f8:	ff010113          	addi	sp,sp,-16
800032fc:	00112623          	sw	ra,12(sp)
80003300:	00812423          	sw	s0,8(sp)
80003304:	01010413          	addi	s0,sp,16
  initlock(&tickslock, "time");
80003308:	00006597          	auipc	a1,0x6
8000330c:	09058593          	addi	a1,a1,144 # 80009398 <userret+0x2f8>
80003310:	00013517          	auipc	a0,0x13
80003314:	3d450513          	addi	a0,a0,980 # 800166e4 <tickslock>
80003318:	ffffe097          	auipc	ra,0xffffe
8000331c:	a54080e7          	jalr	-1452(ra) # 80000d6c <initlock>
}
80003320:	00c12083          	lw	ra,12(sp)
80003324:	00812403          	lw	s0,8(sp)
80003328:	01010113          	addi	sp,sp,16
8000332c:	00008067          	ret

80003330 <trapinithart>:

// set up to take exceptions and traps while in the kernel.
void
trapinithart(void)
{
80003330:	ff010113          	addi	sp,sp,-16
80003334:	00112623          	sw	ra,12(sp)
80003338:	00812423          	sw	s0,8(sp)
8000333c:	01010413          	addi	s0,sp,16
  asm volatile("csrw stvec, %0" : : "r" (x));
80003340:	00005797          	auipc	a5,0x5
80003344:	9d078793          	addi	a5,a5,-1584 # 80007d10 <kernelvec>
80003348:	10579073          	csrw	stvec,a5
  w_stvec((uint32)kernelvec);
}
8000334c:	00c12083          	lw	ra,12(sp)
80003350:	00812403          	lw	s0,8(sp)
80003354:	01010113          	addi	sp,sp,16
80003358:	00008067          	ret

8000335c <usertrapret>:
//
// return to user space
//
void
usertrapret(void)
{
8000335c:	ff010113          	addi	sp,sp,-16
80003360:	00112623          	sw	ra,12(sp)
80003364:	00812423          	sw	s0,8(sp)
80003368:	01010413          	addi	s0,sp,16
  struct proc *p = myproc();
8000336c:	fffff097          	auipc	ra,0xfffff
80003370:	f70080e7          	jalr	-144(ra) # 800022dc <myproc>
  asm volatile("csrr %0, sstatus" : "=r" (x) );
80003374:	100027f3          	csrr	a5,sstatus
  w_sstatus(r_sstatus() & ~SSTATUS_SIE);
80003378:	ffd7f793          	andi	a5,a5,-3
  asm volatile("csrw sstatus, %0" : : "r" (x));
8000337c:	10079073          	csrw	sstatus,a5
  // turn off interrupts, since we're switching
  // now from kerneltrap() to usertrap().
  intr_off();

  // send syscalls, interrupts, and exceptions to trampoline.S
  w_stvec(TRAMPOLINE + (uservec - trampoline));
80003380:	00006617          	auipc	a2,0x6
80003384:	c8060613          	addi	a2,a2,-896 # 80009000 <trampoline>
80003388:	00005797          	auipc	a5,0x5
8000338c:	c7878793          	addi	a5,a5,-904 # 80008000 <free_desc+0x60>
80003390:	40c787b3          	sub	a5,a5,a2
  asm volatile("csrw stvec, %0" : : "r" (x));
80003394:	10579073          	csrw	stvec,a5

  // set up trapframe values that uservec will need when
  // the process next re-enters the kernel.
  p->tf->kernel_satp = r_satp();         // kernel page table
80003398:	03052783          	lw	a5,48(a0)
  asm volatile("csrr %0, satp" : "=r" (x) );
8000339c:	18002773          	csrr	a4,satp
800033a0:	00e7a023          	sw	a4,0(a5)
  p->tf->kernel_sp = p->kstack + PGSIZE; // process's kernel stack
800033a4:	03052703          	lw	a4,48(a0)
800033a8:	02452783          	lw	a5,36(a0)
800033ac:	000016b7          	lui	a3,0x1
800033b0:	00d787b3          	add	a5,a5,a3
800033b4:	00f72223          	sw	a5,4(a4)
  p->tf->kernel_trap = (uint32)usertrap;
800033b8:	03052783          	lw	a5,48(a0)
800033bc:	00000717          	auipc	a4,0x0
800033c0:	19470713          	addi	a4,a4,404 # 80003550 <usertrap>
800033c4:	00e7a423          	sw	a4,8(a5)
  p->tf->kernel_hartid = r_tp();         // hartid for cpuid()
800033c8:	03052783          	lw	a5,48(a0)
  asm volatile("mv %0, tp" : "=r" (x) );
800033cc:	00020713          	mv	a4,tp
800033d0:	00e7a823          	sw	a4,16(a5)
  asm volatile("csrr %0, sstatus" : "=r" (x) );
800033d4:	100027f3          	csrr	a5,sstatus
  // set up the registers that trampoline.S's sret will use
  // to get to user space.
  
  // set S Previous Privilege mode to User.
  unsigned long x = r_sstatus();
  x &= ~SSTATUS_SPP; // clear SPP to 0 for user mode
800033d8:	eff7f793          	andi	a5,a5,-257
  x |= SSTATUS_SPIE; // enable interrupts in user mode
800033dc:	0207e793          	ori	a5,a5,32
  asm volatile("csrw sstatus, %0" : : "r" (x));
800033e0:	10079073          	csrw	sstatus,a5
  w_sstatus(x);

  // set S Exception Program Counter to the saved user pc.
  w_sepc(p->tf->epc);
800033e4:	03052783          	lw	a5,48(a0)
  asm volatile("csrw sepc, %0" : : "r" (x));
800033e8:	00c7a783          	lw	a5,12(a5)
800033ec:	14179073          	csrw	sepc,a5

  // tell trampoline.S the user page table to switch to.
  uint32 satp = MAKE_SATP(p->pagetable);
800033f0:	02c52703          	lw	a4,44(a0)
800033f4:	00c75713          	srli	a4,a4,0xc

  // jump to trampoline.S at the top of memory, which 
  // switches to the user page table, restores user registers,
  // and switches to user mode with sret.
  uint32 fn = TRAMPOLINE + (userret - trampoline);
800033f8:	00006797          	auipc	a5,0x6
800033fc:	ca878793          	addi	a5,a5,-856 # 800090a0 <userret>
80003400:	40c787b3          	sub	a5,a5,a2
80003404:	40d787b3          	sub	a5,a5,a3
  ((void (*)(uint32,uint32))fn)(TRAPFRAME, satp);
80003408:	800005b7          	lui	a1,0x80000
8000340c:	00b765b3          	or	a1,a4,a1
80003410:	ffffe537          	lui	a0,0xffffe
80003414:	000780e7          	jalr	a5
}
80003418:	00c12083          	lw	ra,12(sp)
8000341c:	00812403          	lw	s0,8(sp)
80003420:	01010113          	addi	sp,sp,16
80003424:	00008067          	ret

80003428 <clockintr>:
  w_sstatus(sstatus);
}

void
clockintr()
{
80003428:	ff010113          	addi	sp,sp,-16
8000342c:	00112623          	sw	ra,12(sp)
80003430:	00812423          	sw	s0,8(sp)
80003434:	01010413          	addi	s0,sp,16
  acquire(&tickslock);
80003438:	00013517          	auipc	a0,0x13
8000343c:	2ac50513          	addi	a0,a0,684 # 800166e4 <tickslock>
80003440:	ffffe097          	auipc	ra,0xffffe
80003444:	abc080e7          	jalr	-1348(ra) # 80000efc <acquire>
  ticks++;
80003448:	00021717          	auipc	a4,0x21
8000344c:	bc870713          	addi	a4,a4,-1080 # 80024010 <ticks>
80003450:	00072783          	lw	a5,0(a4)
80003454:	00178793          	addi	a5,a5,1
80003458:	00f72023          	sw	a5,0(a4)
  wakeup(&ticks);
8000345c:	00070513          	mv	a0,a4
80003460:	00000097          	auipc	ra,0x0
80003464:	acc080e7          	jalr	-1332(ra) # 80002f2c <wakeup>
  release(&tickslock);
80003468:	00013517          	auipc	a0,0x13
8000346c:	27c50513          	addi	a0,a0,636 # 800166e4 <tickslock>
80003470:	ffffe097          	auipc	ra,0xffffe
80003474:	b00080e7          	jalr	-1280(ra) # 80000f70 <release>
}
80003478:	00c12083          	lw	ra,12(sp)
8000347c:	00812403          	lw	s0,8(sp)
80003480:	01010113          	addi	sp,sp,16
80003484:	00008067          	ret

80003488 <devintr>:
  asm volatile("csrr %0, scause" : "=r" (x) );
80003488:	142027f3          	csrr	a5,scause
    // the SSIP bit in sip.
    w_sip(r_sip() & ~2);

    return 2;
  } else {
    return 0;
8000348c:	00000513          	li	a0,0
  if((scause & 0x80000000L) &&
80003490:	0a07de63          	bgez	a5,8000354c <devintr+0xc4>
{
80003494:	ff010113          	addi	sp,sp,-16
80003498:	00112623          	sw	ra,12(sp)
8000349c:	00812423          	sw	s0,8(sp)
800034a0:	01010413          	addi	s0,sp,16
     (scause & 0xff) == 9){
800034a4:	0ff7f713          	zext.b	a4,a5
  if((scause & 0x80000000L) &&
800034a8:	00900693          	li	a3,9
800034ac:	02d70263          	beq	a4,a3,800034d0 <devintr+0x48>
  } else if(scause == 0x80000001L){
800034b0:	80000737          	lui	a4,0x80000
800034b4:	00170713          	addi	a4,a4,1 # 80000001 <_entry+0x1>
    return 0;
800034b8:	00000513          	li	a0,0
  } else if(scause == 0x80000001L){
800034bc:	06e78263          	beq	a5,a4,80003520 <devintr+0x98>
  }
}
800034c0:	00c12083          	lw	ra,12(sp)
800034c4:	00812403          	lw	s0,8(sp)
800034c8:	01010113          	addi	sp,sp,16
800034cc:	00008067          	ret
800034d0:	00912223          	sw	s1,4(sp)
    int irq = plic_claim();
800034d4:	00005097          	auipc	ra,0x5
800034d8:	a50080e7          	jalr	-1456(ra) # 80007f24 <plic_claim>
800034dc:	00050493          	mv	s1,a0
    if(irq == UART0_IRQ){
800034e0:	00a00793          	li	a5,10
800034e4:	02f50263          	beq	a0,a5,80003508 <devintr+0x80>
    } else if(irq == VIRTIO0_IRQ){
800034e8:	00100793          	li	a5,1
800034ec:	02f50463          	beq	a0,a5,80003514 <devintr+0x8c>
    plic_complete(irq);
800034f0:	00048513          	mv	a0,s1
800034f4:	00005097          	auipc	ra,0x5
800034f8:	a68080e7          	jalr	-1432(ra) # 80007f5c <plic_complete>
    return 1;
800034fc:	00100513          	li	a0,1
80003500:	00412483          	lw	s1,4(sp)
80003504:	fbdff06f          	j	800034c0 <devintr+0x38>
      uartintr();
80003508:	ffffd097          	auipc	ra,0xffffd
8000350c:	624080e7          	jalr	1572(ra) # 80000b2c <uartintr>
80003510:	fe1ff06f          	j	800034f0 <devintr+0x68>
      virtio_disk_intr();
80003514:	00005097          	auipc	ra,0x5
80003518:	020080e7          	jalr	32(ra) # 80008534 <virtio_disk_intr>
8000351c:	fd5ff06f          	j	800034f0 <devintr+0x68>
    if(cpuid() == 0){
80003520:	fffff097          	auipc	ra,0xfffff
80003524:	d5c080e7          	jalr	-676(ra) # 8000227c <cpuid>
80003528:	00050c63          	beqz	a0,80003540 <devintr+0xb8>
  asm volatile("csrr %0, sip" : "=r" (x) );
8000352c:	144027f3          	csrr	a5,sip
    w_sip(r_sip() & ~2);
80003530:	ffd7f793          	andi	a5,a5,-3
  asm volatile("csrw sip, %0" : : "r" (x));
80003534:	14479073          	csrw	sip,a5
    return 2;
80003538:	00200513          	li	a0,2
8000353c:	f85ff06f          	j	800034c0 <devintr+0x38>
      clockintr();
80003540:	00000097          	auipc	ra,0x0
80003544:	ee8080e7          	jalr	-280(ra) # 80003428 <clockintr>
80003548:	fe5ff06f          	j	8000352c <devintr+0xa4>
}
8000354c:	00008067          	ret

80003550 <usertrap>:
{
80003550:	ff010113          	addi	sp,sp,-16
80003554:	00112623          	sw	ra,12(sp)
80003558:	00812423          	sw	s0,8(sp)
8000355c:	00912223          	sw	s1,4(sp)
80003560:	01212023          	sw	s2,0(sp)
80003564:	01010413          	addi	s0,sp,16
  asm volatile("csrr %0, sstatus" : "=r" (x) );
80003568:	100027f3          	csrr	a5,sstatus
  if((r_sstatus() & SSTATUS_SPP) != 0)
8000356c:	1007f793          	andi	a5,a5,256
80003570:	08079a63          	bnez	a5,80003604 <usertrap+0xb4>
  asm volatile("csrw stvec, %0" : : "r" (x));
80003574:	00004797          	auipc	a5,0x4
80003578:	79c78793          	addi	a5,a5,1948 # 80007d10 <kernelvec>
8000357c:	10579073          	csrw	stvec,a5
  struct proc *p = myproc();
80003580:	fffff097          	auipc	ra,0xfffff
80003584:	d5c080e7          	jalr	-676(ra) # 800022dc <myproc>
80003588:	00050493          	mv	s1,a0
  p->tf->epc = r_sepc();
8000358c:	03052783          	lw	a5,48(a0)
  asm volatile("csrr %0, sepc" : "=r" (x) );
80003590:	14102773          	csrr	a4,sepc
80003594:	00e7a623          	sw	a4,12(a5)
  asm volatile("csrr %0, scause" : "=r" (x) );
80003598:	14202773          	csrr	a4,scause
  if(r_scause() == 8){
8000359c:	00800793          	li	a5,8
800035a0:	08f71263          	bne	a4,a5,80003624 <usertrap+0xd4>
    if(p->killed)
800035a4:	01852783          	lw	a5,24(a0)
800035a8:	06079663          	bnez	a5,80003614 <usertrap+0xc4>
    p->tf->epc += 4;
800035ac:	0304a703          	lw	a4,48(s1)
800035b0:	00c72783          	lw	a5,12(a4)
800035b4:	00478793          	addi	a5,a5,4
800035b8:	00f72623          	sw	a5,12(a4)
  asm volatile("csrr %0, sie" : "=r" (x) );
800035bc:	104027f3          	csrr	a5,sie
  w_sie(r_sie() | SIE_SEIE | SIE_STIE | SIE_SSIE);
800035c0:	2227e793          	ori	a5,a5,546
  asm volatile("csrw sie, %0" : : "r" (x));
800035c4:	10479073          	csrw	sie,a5
  asm volatile("csrr %0, sstatus" : "=r" (x) );
800035c8:	100027f3          	csrr	a5,sstatus
  w_sstatus(r_sstatus() | SSTATUS_SIE);
800035cc:	0027e793          	ori	a5,a5,2
  asm volatile("csrw sstatus, %0" : : "r" (x));
800035d0:	10079073          	csrw	sstatus,a5
    syscall();
800035d4:	00000097          	auipc	ra,0x0
800035d8:	434080e7          	jalr	1076(ra) # 80003a08 <syscall>
  if(p->killed)
800035dc:	0184a783          	lw	a5,24(s1)
800035e0:	0a079c63          	bnez	a5,80003698 <usertrap+0x148>
  usertrapret();
800035e4:	00000097          	auipc	ra,0x0
800035e8:	d78080e7          	jalr	-648(ra) # 8000335c <usertrapret>
}
800035ec:	00c12083          	lw	ra,12(sp)
800035f0:	00812403          	lw	s0,8(sp)
800035f4:	00412483          	lw	s1,4(sp)
800035f8:	00012903          	lw	s2,0(sp)
800035fc:	01010113          	addi	sp,sp,16
80003600:	00008067          	ret
    panic("usertrap: not from user mode");
80003604:	00006517          	auipc	a0,0x6
80003608:	d9c50513          	addi	a0,a0,-612 # 800093a0 <userret+0x300>
8000360c:	ffffd097          	auipc	ra,0xffffd
80003610:	0f0080e7          	jalr	240(ra) # 800006fc <panic>
      exit(-1);
80003614:	fff00513          	li	a0,-1
80003618:	fffff097          	auipc	ra,0xfffff
8000361c:	570080e7          	jalr	1392(ra) # 80002b88 <exit>
80003620:	f8dff06f          	j	800035ac <usertrap+0x5c>
  } else if((which_dev = devintr()) != 0){
80003624:	00000097          	auipc	ra,0x0
80003628:	e64080e7          	jalr	-412(ra) # 80003488 <devintr>
8000362c:	00050913          	mv	s2,a0
80003630:	00050863          	beqz	a0,80003640 <usertrap+0xf0>
  if(p->killed)
80003634:	0184a783          	lw	a5,24(s1)
80003638:	04078663          	beqz	a5,80003684 <usertrap+0x134>
8000363c:	03c0006f          	j	80003678 <usertrap+0x128>
  asm volatile("csrr %0, scause" : "=r" (x) );
80003640:	142025f3          	csrr	a1,scause
    printf("usertrap(): unexpected scause %p pid=%d\n", r_scause(), p->pid);
80003644:	0204a603          	lw	a2,32(s1)
80003648:	00006517          	auipc	a0,0x6
8000364c:	d7850513          	addi	a0,a0,-648 # 800093c0 <userret+0x320>
80003650:	ffffd097          	auipc	ra,0xffffd
80003654:	108080e7          	jalr	264(ra) # 80000758 <printf>
  asm volatile("csrr %0, sepc" : "=r" (x) );
80003658:	141025f3          	csrr	a1,sepc
  asm volatile("csrr %0, stval" : "=r" (x) );
8000365c:	14302673          	csrr	a2,stval
    printf("            sepc=%p stval=%p\n", r_sepc(), r_stval());
80003660:	00006517          	auipc	a0,0x6
80003664:	d8c50513          	addi	a0,a0,-628 # 800093ec <userret+0x34c>
80003668:	ffffd097          	auipc	ra,0xffffd
8000366c:	0f0080e7          	jalr	240(ra) # 80000758 <printf>
    p->killed = 1;
80003670:	00100793          	li	a5,1
80003674:	00f4ac23          	sw	a5,24(s1)
    exit(-1);
80003678:	fff00513          	li	a0,-1
8000367c:	fffff097          	auipc	ra,0xfffff
80003680:	50c080e7          	jalr	1292(ra) # 80002b88 <exit>
  if(which_dev == 2)
80003684:	00200793          	li	a5,2
80003688:	f4f91ee3          	bne	s2,a5,800035e4 <usertrap+0x94>
    yield();
8000368c:	fffff097          	auipc	ra,0xfffff
80003690:	638080e7          	jalr	1592(ra) # 80002cc4 <yield>
80003694:	f51ff06f          	j	800035e4 <usertrap+0x94>
  int which_dev = 0;
80003698:	00000913          	li	s2,0
8000369c:	fddff06f          	j	80003678 <usertrap+0x128>

800036a0 <kerneltrap>:
{
800036a0:	fe010113          	addi	sp,sp,-32
800036a4:	00112e23          	sw	ra,28(sp)
800036a8:	00812c23          	sw	s0,24(sp)
800036ac:	00912a23          	sw	s1,20(sp)
800036b0:	01212823          	sw	s2,16(sp)
800036b4:	01312623          	sw	s3,12(sp)
800036b8:	02010413          	addi	s0,sp,32
  asm volatile("csrr %0, sepc" : "=r" (x) );
800036bc:	14102973          	csrr	s2,sepc
  asm volatile("csrr %0, sstatus" : "=r" (x) );
800036c0:	100024f3          	csrr	s1,sstatus
  asm volatile("csrr %0, scause" : "=r" (x) );
800036c4:	142027f3          	csrr	a5,scause
800036c8:	00078993          	mv	s3,a5
  if((sstatus & SSTATUS_SPP) == 0)
800036cc:	1004f793          	andi	a5,s1,256
800036d0:	04078463          	beqz	a5,80003718 <kerneltrap+0x78>
  asm volatile("csrr %0, sstatus" : "=r" (x) );
800036d4:	100027f3          	csrr	a5,sstatus
  return (x & SSTATUS_SIE) != 0;
800036d8:	0027f793          	andi	a5,a5,2
  if(intr_get() != 0)
800036dc:	04079663          	bnez	a5,80003728 <kerneltrap+0x88>
  if((which_dev = devintr()) == 0){
800036e0:	00000097          	auipc	ra,0x0
800036e4:	da8080e7          	jalr	-600(ra) # 80003488 <devintr>
800036e8:	04050863          	beqz	a0,80003738 <kerneltrap+0x98>
  if(which_dev == 2 && myproc() != 0 && myproc()->state == RUNNING)
800036ec:	00200793          	li	a5,2
800036f0:	08f50263          	beq	a0,a5,80003774 <kerneltrap+0xd4>
  asm volatile("csrw sepc, %0" : : "r" (x));
800036f4:	14191073          	csrw	sepc,s2
  asm volatile("csrw sstatus, %0" : : "r" (x));
800036f8:	10049073          	csrw	sstatus,s1
}
800036fc:	01c12083          	lw	ra,28(sp)
80003700:	01812403          	lw	s0,24(sp)
80003704:	01412483          	lw	s1,20(sp)
80003708:	01012903          	lw	s2,16(sp)
8000370c:	00c12983          	lw	s3,12(sp)
80003710:	02010113          	addi	sp,sp,32
80003714:	00008067          	ret
    panic("kerneltrap: not from supervisor mode");
80003718:	00006517          	auipc	a0,0x6
8000371c:	cf450513          	addi	a0,a0,-780 # 8000940c <userret+0x36c>
80003720:	ffffd097          	auipc	ra,0xffffd
80003724:	fdc080e7          	jalr	-36(ra) # 800006fc <panic>
    panic("kerneltrap: interrupts enabled");
80003728:	00006517          	auipc	a0,0x6
8000372c:	d0c50513          	addi	a0,a0,-756 # 80009434 <userret+0x394>
80003730:	ffffd097          	auipc	ra,0xffffd
80003734:	fcc080e7          	jalr	-52(ra) # 800006fc <panic>
    printf("scause %p\n", scause);
80003738:	00098593          	mv	a1,s3
8000373c:	00006517          	auipc	a0,0x6
80003740:	d1850513          	addi	a0,a0,-744 # 80009454 <userret+0x3b4>
80003744:	ffffd097          	auipc	ra,0xffffd
80003748:	014080e7          	jalr	20(ra) # 80000758 <printf>
  asm volatile("csrr %0, sepc" : "=r" (x) );
8000374c:	141025f3          	csrr	a1,sepc
  asm volatile("csrr %0, stval" : "=r" (x) );
80003750:	14302673          	csrr	a2,stval
    printf("sepc=%p stval=%p\n", r_sepc(), r_stval());
80003754:	00006517          	auipc	a0,0x6
80003758:	ca450513          	addi	a0,a0,-860 # 800093f8 <userret+0x358>
8000375c:	ffffd097          	auipc	ra,0xffffd
80003760:	ffc080e7          	jalr	-4(ra) # 80000758 <printf>
    panic("kerneltrap");
80003764:	00006517          	auipc	a0,0x6
80003768:	cfc50513          	addi	a0,a0,-772 # 80009460 <userret+0x3c0>
8000376c:	ffffd097          	auipc	ra,0xffffd
80003770:	f90080e7          	jalr	-112(ra) # 800006fc <panic>
  if(which_dev == 2 && myproc() != 0 && myproc()->state == RUNNING)
80003774:	fffff097          	auipc	ra,0xfffff
80003778:	b68080e7          	jalr	-1176(ra) # 800022dc <myproc>
8000377c:	f6050ce3          	beqz	a0,800036f4 <kerneltrap+0x54>
80003780:	fffff097          	auipc	ra,0xfffff
80003784:	b5c080e7          	jalr	-1188(ra) # 800022dc <myproc>
80003788:	00c52703          	lw	a4,12(a0)
8000378c:	00300793          	li	a5,3
80003790:	f6f712e3          	bne	a4,a5,800036f4 <kerneltrap+0x54>
    yield();
80003794:	fffff097          	auipc	ra,0xfffff
80003798:	530080e7          	jalr	1328(ra) # 80002cc4 <yield>
8000379c:	f59ff06f          	j	800036f4 <kerneltrap+0x54>

800037a0 <argraw>:
  return strlen(buf);
}

static uint32
argraw(int n)
{
800037a0:	ff010113          	addi	sp,sp,-16
800037a4:	00112623          	sw	ra,12(sp)
800037a8:	00812423          	sw	s0,8(sp)
800037ac:	00912223          	sw	s1,4(sp)
800037b0:	01010413          	addi	s0,sp,16
800037b4:	00050493          	mv	s1,a0
  struct proc *p = myproc();
800037b8:	fffff097          	auipc	ra,0xfffff
800037bc:	b24080e7          	jalr	-1244(ra) # 800022dc <myproc>
  switch (n) {
800037c0:	00500793          	li	a5,5
800037c4:	0697ec63          	bltu	a5,s1,8000383c <argraw+0x9c>
800037c8:	00249493          	slli	s1,s1,0x2
800037cc:	00006717          	auipc	a4,0x6
800037d0:	04870713          	addi	a4,a4,72 # 80009814 <states.0+0x14>
800037d4:	00e484b3          	add	s1,s1,a4
800037d8:	0004a783          	lw	a5,0(s1)
800037dc:	00e787b3          	add	a5,a5,a4
800037e0:	00078067          	jr	a5
  case 0:
    return p->tf->a0;
800037e4:	03052783          	lw	a5,48(a0)
800037e8:	0387a503          	lw	a0,56(a5)
  case 5:
    return p->tf->a5;
  }
  panic("argraw");
  return -1;
}
800037ec:	00c12083          	lw	ra,12(sp)
800037f0:	00812403          	lw	s0,8(sp)
800037f4:	00412483          	lw	s1,4(sp)
800037f8:	01010113          	addi	sp,sp,16
800037fc:	00008067          	ret
    return p->tf->a1;
80003800:	03052783          	lw	a5,48(a0)
80003804:	03c7a503          	lw	a0,60(a5)
80003808:	fe5ff06f          	j	800037ec <argraw+0x4c>
    return p->tf->a2;
8000380c:	03052783          	lw	a5,48(a0)
80003810:	0407a503          	lw	a0,64(a5)
80003814:	fd9ff06f          	j	800037ec <argraw+0x4c>
    return p->tf->a3;
80003818:	03052783          	lw	a5,48(a0)
8000381c:	0447a503          	lw	a0,68(a5)
80003820:	fcdff06f          	j	800037ec <argraw+0x4c>
    return p->tf->a4;
80003824:	03052783          	lw	a5,48(a0)
80003828:	0487a503          	lw	a0,72(a5)
8000382c:	fc1ff06f          	j	800037ec <argraw+0x4c>
    return p->tf->a5;
80003830:	03052783          	lw	a5,48(a0)
80003834:	04c7a503          	lw	a0,76(a5)
80003838:	fb5ff06f          	j	800037ec <argraw+0x4c>
  panic("argraw");
8000383c:	00006517          	auipc	a0,0x6
80003840:	c3050513          	addi	a0,a0,-976 # 8000946c <userret+0x3cc>
80003844:	ffffd097          	auipc	ra,0xffffd
80003848:	eb8080e7          	jalr	-328(ra) # 800006fc <panic>

8000384c <fetchaddr>:
{
8000384c:	ff010113          	addi	sp,sp,-16
80003850:	00112623          	sw	ra,12(sp)
80003854:	00812423          	sw	s0,8(sp)
80003858:	00912223          	sw	s1,4(sp)
8000385c:	01212023          	sw	s2,0(sp)
80003860:	01010413          	addi	s0,sp,16
80003864:	00050493          	mv	s1,a0
80003868:	00058913          	mv	s2,a1
  struct proc *p = myproc();
8000386c:	fffff097          	auipc	ra,0xfffff
80003870:	a70080e7          	jalr	-1424(ra) # 800022dc <myproc>
  if(addr >= p->sz || addr+sizeof(uint32) > p->sz)
80003874:	02852783          	lw	a5,40(a0)
80003878:	04f4f263          	bgeu	s1,a5,800038bc <fetchaddr+0x70>
8000387c:	00448713          	addi	a4,s1,4
80003880:	04e7e263          	bltu	a5,a4,800038c4 <fetchaddr+0x78>
  if(copyin(p->pagetable, (char *)ip, addr, sizeof(*ip)) != 0)
80003884:	00400693          	li	a3,4
80003888:	00048613          	mv	a2,s1
8000388c:	00090593          	mv	a1,s2
80003890:	02c52503          	lw	a0,44(a0)
80003894:	ffffe097          	auipc	ra,0xffffe
80003898:	650080e7          	jalr	1616(ra) # 80001ee4 <copyin>
8000389c:	00a03533          	snez	a0,a0
800038a0:	40a00533          	neg	a0,a0
}
800038a4:	00c12083          	lw	ra,12(sp)
800038a8:	00812403          	lw	s0,8(sp)
800038ac:	00412483          	lw	s1,4(sp)
800038b0:	00012903          	lw	s2,0(sp)
800038b4:	01010113          	addi	sp,sp,16
800038b8:	00008067          	ret
    return -1;
800038bc:	fff00513          	li	a0,-1
800038c0:	fe5ff06f          	j	800038a4 <fetchaddr+0x58>
800038c4:	fff00513          	li	a0,-1
800038c8:	fddff06f          	j	800038a4 <fetchaddr+0x58>

800038cc <fetchstr>:
{
800038cc:	fe010113          	addi	sp,sp,-32
800038d0:	00112e23          	sw	ra,28(sp)
800038d4:	00812c23          	sw	s0,24(sp)
800038d8:	00912a23          	sw	s1,20(sp)
800038dc:	01212823          	sw	s2,16(sp)
800038e0:	01312623          	sw	s3,12(sp)
800038e4:	02010413          	addi	s0,sp,32
800038e8:	00050993          	mv	s3,a0
800038ec:	00058493          	mv	s1,a1
800038f0:	00060913          	mv	s2,a2
  struct proc *p = myproc();
800038f4:	fffff097          	auipc	ra,0xfffff
800038f8:	9e8080e7          	jalr	-1560(ra) # 800022dc <myproc>
  int err = copyinstr(p->pagetable, buf, addr, max);
800038fc:	00090693          	mv	a3,s2
80003900:	00098613          	mv	a2,s3
80003904:	00048593          	mv	a1,s1
80003908:	02c52503          	lw	a0,44(a0)
8000390c:	ffffe097          	auipc	ra,0xffffe
80003910:	6c0080e7          	jalr	1728(ra) # 80001fcc <copyinstr>
  if(err < 0)
80003914:	00054863          	bltz	a0,80003924 <fetchstr+0x58>
  return strlen(buf);
80003918:	00048513          	mv	a0,s1
8000391c:	ffffe097          	auipc	ra,0xffffe
80003920:	8e8080e7          	jalr	-1816(ra) # 80001204 <strlen>
}
80003924:	01c12083          	lw	ra,28(sp)
80003928:	01812403          	lw	s0,24(sp)
8000392c:	01412483          	lw	s1,20(sp)
80003930:	01012903          	lw	s2,16(sp)
80003934:	00c12983          	lw	s3,12(sp)
80003938:	02010113          	addi	sp,sp,32
8000393c:	00008067          	ret

80003940 <argint>:

// Fetch the nth 32-bit system call argument.
int
argint(int n, int *ip)
{
80003940:	ff010113          	addi	sp,sp,-16
80003944:	00112623          	sw	ra,12(sp)
80003948:	00812423          	sw	s0,8(sp)
8000394c:	00912223          	sw	s1,4(sp)
80003950:	01010413          	addi	s0,sp,16
80003954:	00058493          	mv	s1,a1
  *ip = argraw(n);
80003958:	00000097          	auipc	ra,0x0
8000395c:	e48080e7          	jalr	-440(ra) # 800037a0 <argraw>
80003960:	00a4a023          	sw	a0,0(s1)
  return 0;
}
80003964:	00000513          	li	a0,0
80003968:	00c12083          	lw	ra,12(sp)
8000396c:	00812403          	lw	s0,8(sp)
80003970:	00412483          	lw	s1,4(sp)
80003974:	01010113          	addi	sp,sp,16
80003978:	00008067          	ret

8000397c <argaddr>:
// Retrieve an argument as a pointer.
// Doesn't check for legality, since
// copyin/copyout will do that.
int
argaddr(int n, uint32 *ip)
{
8000397c:	ff010113          	addi	sp,sp,-16
80003980:	00112623          	sw	ra,12(sp)
80003984:	00812423          	sw	s0,8(sp)
80003988:	00912223          	sw	s1,4(sp)
8000398c:	01010413          	addi	s0,sp,16
80003990:	00058493          	mv	s1,a1
  *ip = argraw(n);
80003994:	00000097          	auipc	ra,0x0
80003998:	e0c080e7          	jalr	-500(ra) # 800037a0 <argraw>
8000399c:	00a4a023          	sw	a0,0(s1)
  return 0;
}
800039a0:	00000513          	li	a0,0
800039a4:	00c12083          	lw	ra,12(sp)
800039a8:	00812403          	lw	s0,8(sp)
800039ac:	00412483          	lw	s1,4(sp)
800039b0:	01010113          	addi	sp,sp,16
800039b4:	00008067          	ret

800039b8 <argstr>:
// Fetch the nth word-sized system call argument as a null-terminated string.
// Copies into buf, at most max.
// Returns string length if OK (including nul), -1 if error.
int
argstr(int n, char *buf, int max)
{
800039b8:	ff010113          	addi	sp,sp,-16
800039bc:	00112623          	sw	ra,12(sp)
800039c0:	00812423          	sw	s0,8(sp)
800039c4:	00912223          	sw	s1,4(sp)
800039c8:	01212023          	sw	s2,0(sp)
800039cc:	01010413          	addi	s0,sp,16
800039d0:	00058913          	mv	s2,a1
800039d4:	00060493          	mv	s1,a2
  *ip = argraw(n);
800039d8:	00000097          	auipc	ra,0x0
800039dc:	dc8080e7          	jalr	-568(ra) # 800037a0 <argraw>
  uint32 addr;
  if(argaddr(n, &addr) < 0)
    return -1;
  return fetchstr(addr, buf, max);
800039e0:	00048613          	mv	a2,s1
800039e4:	00090593          	mv	a1,s2
800039e8:	00000097          	auipc	ra,0x0
800039ec:	ee4080e7          	jalr	-284(ra) # 800038cc <fetchstr>
}
800039f0:	00c12083          	lw	ra,12(sp)
800039f4:	00812403          	lw	s0,8(sp)
800039f8:	00412483          	lw	s1,4(sp)
800039fc:	00012903          	lw	s2,0(sp)
80003a00:	01010113          	addi	sp,sp,16
80003a04:	00008067          	ret

80003a08 <syscall>:
[SYS_close]   sys_close,
};

void
syscall(void)
{
80003a08:	ff010113          	addi	sp,sp,-16
80003a0c:	00112623          	sw	ra,12(sp)
80003a10:	00812423          	sw	s0,8(sp)
80003a14:	00912223          	sw	s1,4(sp)
80003a18:	01212023          	sw	s2,0(sp)
80003a1c:	01010413          	addi	s0,sp,16
  int num;
  struct proc *p = myproc();
80003a20:	fffff097          	auipc	ra,0xfffff
80003a24:	8bc080e7          	jalr	-1860(ra) # 800022dc <myproc>
80003a28:	00050493          	mv	s1,a0

  num = p->tf->a7;
80003a2c:	03052903          	lw	s2,48(a0)
80003a30:	05492683          	lw	a3,84(s2)
  if(num > 0 && num < NELEM(syscalls) && syscalls[num]) {
80003a34:	fff68713          	addi	a4,a3,-1 # fff <_entry-0x7ffff001>
80003a38:	01400793          	li	a5,20
80003a3c:	02e7e463          	bltu	a5,a4,80003a64 <syscall+0x5c>
80003a40:	00269713          	slli	a4,a3,0x2
80003a44:	00006797          	auipc	a5,0x6
80003a48:	de878793          	addi	a5,a5,-536 # 8000982c <syscalls>
80003a4c:	00e787b3          	add	a5,a5,a4
80003a50:	0007a783          	lw	a5,0(a5)
80003a54:	00078863          	beqz	a5,80003a64 <syscall+0x5c>
    p->tf->a0 = syscalls[num]();
80003a58:	000780e7          	jalr	a5
80003a5c:	02a92c23          	sw	a0,56(s2)
80003a60:	0280006f          	j	80003a88 <syscall+0x80>
  } else {
    printf("%d %s: unknown sys call %d\n",
80003a64:	0b048613          	addi	a2,s1,176
80003a68:	0204a583          	lw	a1,32(s1)
80003a6c:	00006517          	auipc	a0,0x6
80003a70:	a0850513          	addi	a0,a0,-1528 # 80009474 <userret+0x3d4>
80003a74:	ffffd097          	auipc	ra,0xffffd
80003a78:	ce4080e7          	jalr	-796(ra) # 80000758 <printf>
            p->pid, p->name, num);
    p->tf->a0 = -1;
80003a7c:	0304a783          	lw	a5,48(s1)
80003a80:	fff00713          	li	a4,-1
80003a84:	02e7ac23          	sw	a4,56(a5)
  }
}
80003a88:	00c12083          	lw	ra,12(sp)
80003a8c:	00812403          	lw	s0,8(sp)
80003a90:	00412483          	lw	s1,4(sp)
80003a94:	00012903          	lw	s2,0(sp)
80003a98:	01010113          	addi	sp,sp,16
80003a9c:	00008067          	ret

80003aa0 <sys_exit>:
#include "spinlock.h"
#include "proc.h"

uint32
sys_exit(void)
{
80003aa0:	fe010113          	addi	sp,sp,-32
80003aa4:	00112e23          	sw	ra,28(sp)
80003aa8:	00812c23          	sw	s0,24(sp)
80003aac:	02010413          	addi	s0,sp,32
  int n;
  if(argint(0, &n) < 0)
80003ab0:	fec40593          	addi	a1,s0,-20
80003ab4:	00000513          	li	a0,0
80003ab8:	00000097          	auipc	ra,0x0
80003abc:	e88080e7          	jalr	-376(ra) # 80003940 <argint>
    return -1;
80003ac0:	fff00793          	li	a5,-1
  if(argint(0, &n) < 0)
80003ac4:	00054a63          	bltz	a0,80003ad8 <sys_exit+0x38>
  exit(n);
80003ac8:	fec42503          	lw	a0,-20(s0)
80003acc:	fffff097          	auipc	ra,0xfffff
80003ad0:	0bc080e7          	jalr	188(ra) # 80002b88 <exit>
  return 0;  // not reached
80003ad4:	00000793          	li	a5,0
}
80003ad8:	00078513          	mv	a0,a5
80003adc:	01c12083          	lw	ra,28(sp)
80003ae0:	01812403          	lw	s0,24(sp)
80003ae4:	02010113          	addi	sp,sp,32
80003ae8:	00008067          	ret

80003aec <sys_getpid>:

uint32
sys_getpid(void)
{
80003aec:	ff010113          	addi	sp,sp,-16
80003af0:	00112623          	sw	ra,12(sp)
80003af4:	00812423          	sw	s0,8(sp)
80003af8:	01010413          	addi	s0,sp,16
  return myproc()->pid;
80003afc:	ffffe097          	auipc	ra,0xffffe
80003b00:	7e0080e7          	jalr	2016(ra) # 800022dc <myproc>
}
80003b04:	02052503          	lw	a0,32(a0)
80003b08:	00c12083          	lw	ra,12(sp)
80003b0c:	00812403          	lw	s0,8(sp)
80003b10:	01010113          	addi	sp,sp,16
80003b14:	00008067          	ret

80003b18 <sys_fork>:

uint32
sys_fork(void)
{
80003b18:	ff010113          	addi	sp,sp,-16
80003b1c:	00112623          	sw	ra,12(sp)
80003b20:	00812423          	sw	s0,8(sp)
80003b24:	01010413          	addi	s0,sp,16
  return fork();
80003b28:	fffff097          	auipc	ra,0xfffff
80003b2c:	c60080e7          	jalr	-928(ra) # 80002788 <fork>
}
80003b30:	00c12083          	lw	ra,12(sp)
80003b34:	00812403          	lw	s0,8(sp)
80003b38:	01010113          	addi	sp,sp,16
80003b3c:	00008067          	ret

80003b40 <sys_wait>:

uint32
sys_wait(void)
{
80003b40:	fe010113          	addi	sp,sp,-32
80003b44:	00112e23          	sw	ra,28(sp)
80003b48:	00812c23          	sw	s0,24(sp)
80003b4c:	02010413          	addi	s0,sp,32
  uint32 p;
  if(argaddr(0, &p) < 0)
80003b50:	fec40593          	addi	a1,s0,-20
80003b54:	00000513          	li	a0,0
80003b58:	00000097          	auipc	ra,0x0
80003b5c:	e24080e7          	jalr	-476(ra) # 8000397c <argaddr>
80003b60:	00050793          	mv	a5,a0
    return -1;
80003b64:	fff00513          	li	a0,-1
  if(argaddr(0, &p) < 0)
80003b68:	0007c863          	bltz	a5,80003b78 <sys_wait+0x38>
  return wait(p);
80003b6c:	fec42503          	lw	a0,-20(s0)
80003b70:	fffff097          	auipc	ra,0xfffff
80003b74:	25c080e7          	jalr	604(ra) # 80002dcc <wait>
}
80003b78:	01c12083          	lw	ra,28(sp)
80003b7c:	01812403          	lw	s0,24(sp)
80003b80:	02010113          	addi	sp,sp,32
80003b84:	00008067          	ret

80003b88 <sys_sbrk>:

uint32
sys_sbrk(void)
{
80003b88:	fe010113          	addi	sp,sp,-32
80003b8c:	00112e23          	sw	ra,28(sp)
80003b90:	00812c23          	sw	s0,24(sp)
80003b94:	00912a23          	sw	s1,20(sp)
80003b98:	02010413          	addi	s0,sp,32
  int addr;
  int n;

  if(argint(0, &n) < 0)
80003b9c:	fec40593          	addi	a1,s0,-20
80003ba0:	00000513          	li	a0,0
80003ba4:	00000097          	auipc	ra,0x0
80003ba8:	d9c080e7          	jalr	-612(ra) # 80003940 <argint>
    return -1;
80003bac:	fff00493          	li	s1,-1
  if(argint(0, &n) < 0)
80003bb0:	02054063          	bltz	a0,80003bd0 <sys_sbrk+0x48>
  addr = myproc()->sz;
80003bb4:	ffffe097          	auipc	ra,0xffffe
80003bb8:	728080e7          	jalr	1832(ra) # 800022dc <myproc>
80003bbc:	02852483          	lw	s1,40(a0)
  if(growproc(n) < 0)
80003bc0:	fec42503          	lw	a0,-20(s0)
80003bc4:	fffff097          	auipc	ra,0xfffff
80003bc8:	b38080e7          	jalr	-1224(ra) # 800026fc <growproc>
80003bcc:	00054e63          	bltz	a0,80003be8 <sys_sbrk+0x60>
    return -1;
  return addr;
}
80003bd0:	00048513          	mv	a0,s1
80003bd4:	01c12083          	lw	ra,28(sp)
80003bd8:	01812403          	lw	s0,24(sp)
80003bdc:	01412483          	lw	s1,20(sp)
80003be0:	02010113          	addi	sp,sp,32
80003be4:	00008067          	ret
    return -1;
80003be8:	fff00493          	li	s1,-1
80003bec:	fe5ff06f          	j	80003bd0 <sys_sbrk+0x48>

80003bf0 <sys_sleep>:

uint32
sys_sleep(void)
{
80003bf0:	fd010113          	addi	sp,sp,-48
80003bf4:	02112623          	sw	ra,44(sp)
80003bf8:	02812423          	sw	s0,40(sp)
80003bfc:	03010413          	addi	s0,sp,48
  int n;
  uint ticks0;

  if(argint(0, &n) < 0)
80003c00:	fdc40593          	addi	a1,s0,-36
80003c04:	00000513          	li	a0,0
80003c08:	00000097          	auipc	ra,0x0
80003c0c:	d38080e7          	jalr	-712(ra) # 80003940 <argint>
    return -1;
80003c10:	fff00793          	li	a5,-1
  if(argint(0, &n) < 0)
80003c14:	08054863          	bltz	a0,80003ca4 <sys_sleep+0xb4>
  acquire(&tickslock);
80003c18:	00013517          	auipc	a0,0x13
80003c1c:	acc50513          	addi	a0,a0,-1332 # 800166e4 <tickslock>
80003c20:	ffffd097          	auipc	ra,0xffffd
80003c24:	2dc080e7          	jalr	732(ra) # 80000efc <acquire>
  ticks0 = ticks;
  while(ticks - ticks0 < n){
80003c28:	fdc42783          	lw	a5,-36(s0)
80003c2c:	06078263          	beqz	a5,80003c90 <sys_sleep+0xa0>
80003c30:	02912223          	sw	s1,36(sp)
80003c34:	03212023          	sw	s2,32(sp)
80003c38:	01312e23          	sw	s3,28(sp)
  ticks0 = ticks;
80003c3c:	00020997          	auipc	s3,0x20
80003c40:	3d49a983          	lw	s3,980(s3) # 80024010 <ticks>
    if(myproc()->killed){
      release(&tickslock);
      return -1;
    }
    sleep(&ticks, &tickslock);
80003c44:	00013917          	auipc	s2,0x13
80003c48:	aa090913          	addi	s2,s2,-1376 # 800166e4 <tickslock>
80003c4c:	00020497          	auipc	s1,0x20
80003c50:	3c448493          	addi	s1,s1,964 # 80024010 <ticks>
    if(myproc()->killed){
80003c54:	ffffe097          	auipc	ra,0xffffe
80003c58:	688080e7          	jalr	1672(ra) # 800022dc <myproc>
80003c5c:	01852783          	lw	a5,24(a0)
80003c60:	04079c63          	bnez	a5,80003cb8 <sys_sleep+0xc8>
    sleep(&ticks, &tickslock);
80003c64:	00090593          	mv	a1,s2
80003c68:	00048513          	mv	a0,s1
80003c6c:	fffff097          	auipc	ra,0xfffff
80003c70:	0b0080e7          	jalr	176(ra) # 80002d1c <sleep>
  while(ticks - ticks0 < n){
80003c74:	0004a783          	lw	a5,0(s1)
80003c78:	413787b3          	sub	a5,a5,s3
80003c7c:	fdc42703          	lw	a4,-36(s0)
80003c80:	fce7eae3          	bltu	a5,a4,80003c54 <sys_sleep+0x64>
80003c84:	02412483          	lw	s1,36(sp)
80003c88:	02012903          	lw	s2,32(sp)
80003c8c:	01c12983          	lw	s3,28(sp)
  }
  release(&tickslock);
80003c90:	00013517          	auipc	a0,0x13
80003c94:	a5450513          	addi	a0,a0,-1452 # 800166e4 <tickslock>
80003c98:	ffffd097          	auipc	ra,0xffffd
80003c9c:	2d8080e7          	jalr	728(ra) # 80000f70 <release>
  return 0;
80003ca0:	00000793          	li	a5,0
}
80003ca4:	00078513          	mv	a0,a5
80003ca8:	02c12083          	lw	ra,44(sp)
80003cac:	02812403          	lw	s0,40(sp)
80003cb0:	03010113          	addi	sp,sp,48
80003cb4:	00008067          	ret
      release(&tickslock);
80003cb8:	00013517          	auipc	a0,0x13
80003cbc:	a2c50513          	addi	a0,a0,-1492 # 800166e4 <tickslock>
80003cc0:	ffffd097          	auipc	ra,0xffffd
80003cc4:	2b0080e7          	jalr	688(ra) # 80000f70 <release>
      return -1;
80003cc8:	fff00793          	li	a5,-1
80003ccc:	02412483          	lw	s1,36(sp)
80003cd0:	02012903          	lw	s2,32(sp)
80003cd4:	01c12983          	lw	s3,28(sp)
80003cd8:	fcdff06f          	j	80003ca4 <sys_sleep+0xb4>

80003cdc <sys_kill>:

uint32
sys_kill(void)
{
80003cdc:	fe010113          	addi	sp,sp,-32
80003ce0:	00112e23          	sw	ra,28(sp)
80003ce4:	00812c23          	sw	s0,24(sp)
80003ce8:	02010413          	addi	s0,sp,32
  int pid;

  if(argint(0, &pid) < 0)
80003cec:	fec40593          	addi	a1,s0,-20
80003cf0:	00000513          	li	a0,0
80003cf4:	00000097          	auipc	ra,0x0
80003cf8:	c4c080e7          	jalr	-948(ra) # 80003940 <argint>
80003cfc:	00050793          	mv	a5,a0
    return -1;
80003d00:	fff00513          	li	a0,-1
  if(argint(0, &pid) < 0)
80003d04:	0007c863          	bltz	a5,80003d14 <sys_kill+0x38>
  return kill(pid);
80003d08:	fec42503          	lw	a0,-20(s0)
80003d0c:	fffff097          	auipc	ra,0xfffff
80003d10:	2c0080e7          	jalr	704(ra) # 80002fcc <kill>
}
80003d14:	01c12083          	lw	ra,28(sp)
80003d18:	01812403          	lw	s0,24(sp)
80003d1c:	02010113          	addi	sp,sp,32
80003d20:	00008067          	ret

80003d24 <sys_uptime>:

// return how many clock tick interrupts have occurred
// since start.
uint32
sys_uptime(void)
{
80003d24:	ff010113          	addi	sp,sp,-16
80003d28:	00112623          	sw	ra,12(sp)
80003d2c:	00812423          	sw	s0,8(sp)
80003d30:	00912223          	sw	s1,4(sp)
80003d34:	01010413          	addi	s0,sp,16
  uint xticks;

  acquire(&tickslock);
80003d38:	00013517          	auipc	a0,0x13
80003d3c:	9ac50513          	addi	a0,a0,-1620 # 800166e4 <tickslock>
80003d40:	ffffd097          	auipc	ra,0xffffd
80003d44:	1bc080e7          	jalr	444(ra) # 80000efc <acquire>
  xticks = ticks;
80003d48:	00020797          	auipc	a5,0x20
80003d4c:	2c87a783          	lw	a5,712(a5) # 80024010 <ticks>
80003d50:	00078493          	mv	s1,a5
  release(&tickslock);
80003d54:	00013517          	auipc	a0,0x13
80003d58:	99050513          	addi	a0,a0,-1648 # 800166e4 <tickslock>
80003d5c:	ffffd097          	auipc	ra,0xffffd
80003d60:	214080e7          	jalr	532(ra) # 80000f70 <release>
  return xticks;
}
80003d64:	00048513          	mv	a0,s1
80003d68:	00c12083          	lw	ra,12(sp)
80003d6c:	00812403          	lw	s0,8(sp)
80003d70:	00412483          	lw	s1,4(sp)
80003d74:	01010113          	addi	sp,sp,16
80003d78:	00008067          	ret

80003d7c <binit>:
  struct buf head;
} bcache;

void
binit(void)
{
80003d7c:	fe010113          	addi	sp,sp,-32
80003d80:	00112e23          	sw	ra,28(sp)
80003d84:	00812c23          	sw	s0,24(sp)
80003d88:	00912a23          	sw	s1,20(sp)
80003d8c:	01212823          	sw	s2,16(sp)
80003d90:	01312623          	sw	s3,12(sp)
80003d94:	01412423          	sw	s4,8(sp)
80003d98:	02010413          	addi	s0,sp,32
  struct buf *b;

  initlock(&bcache.lock, "bcache");
80003d9c:	00005597          	auipc	a1,0x5
80003da0:	6f458593          	addi	a1,a1,1780 # 80009490 <userret+0x3f0>
80003da4:	00013517          	auipc	a0,0x13
80003da8:	94c50513          	addi	a0,a0,-1716 # 800166f0 <bcache>
80003dac:	ffffd097          	auipc	ra,0xffffd
80003db0:	fc0080e7          	jalr	-64(ra) # 80000d6c <initlock>

  // Create linked list of buffers
  bcache.head.prev = &bcache.head;
80003db4:	0001b797          	auipc	a5,0x1b
80003db8:	93c78793          	addi	a5,a5,-1732 # 8001e6f0 <bcache+0x8000>
80003dbc:	0001a717          	auipc	a4,0x1a
80003dc0:	7d070713          	addi	a4,a4,2000 # 8001e58c <bcache+0x7e9c>
80003dc4:	ece7a423          	sw	a4,-312(a5)
  bcache.head.next = &bcache.head;
80003dc8:	ece7a623          	sw	a4,-308(a5)
  for(b = bcache.buf; b < bcache.buf+NBUF; b++){
80003dcc:	00013497          	auipc	s1,0x13
80003dd0:	93048493          	addi	s1,s1,-1744 # 800166fc <bcache+0xc>
    b->next = bcache.head.next;
80003dd4:	00078913          	mv	s2,a5
    b->prev = &bcache.head;
80003dd8:	00070993          	mv	s3,a4
    initsleeplock(&b->lock, "buffer");
80003ddc:	00005a17          	auipc	s4,0x5
80003de0:	6bca0a13          	addi	s4,s4,1724 # 80009498 <userret+0x3f8>
    b->next = bcache.head.next;
80003de4:	ecc92783          	lw	a5,-308(s2)
80003de8:	02f4a823          	sw	a5,48(s1)
    b->prev = &bcache.head;
80003dec:	0334a623          	sw	s3,44(s1)
    initsleeplock(&b->lock, "buffer");
80003df0:	000a0593          	mv	a1,s4
80003df4:	01048513          	addi	a0,s1,16
80003df8:	00002097          	auipc	ra,0x2
80003dfc:	c1c080e7          	jalr	-996(ra) # 80005a14 <initsleeplock>
    bcache.head.next->prev = b;
80003e00:	ecc92783          	lw	a5,-308(s2)
80003e04:	0297a623          	sw	s1,44(a5)
    bcache.head.next = b;
80003e08:	ec992623          	sw	s1,-308(s2)
  for(b = bcache.buf; b < bcache.buf+NBUF; b++){
80003e0c:	43848493          	addi	s1,s1,1080
80003e10:	fd349ae3          	bne	s1,s3,80003de4 <binit+0x68>
  }
}
80003e14:	01c12083          	lw	ra,28(sp)
80003e18:	01812403          	lw	s0,24(sp)
80003e1c:	01412483          	lw	s1,20(sp)
80003e20:	01012903          	lw	s2,16(sp)
80003e24:	00c12983          	lw	s3,12(sp)
80003e28:	00812a03          	lw	s4,8(sp)
80003e2c:	02010113          	addi	sp,sp,32
80003e30:	00008067          	ret

80003e34 <bread>:
}

// Return a locked buf with the contents of the indicated block.
struct buf*
bread(uint dev, uint blockno)
{
80003e34:	fe010113          	addi	sp,sp,-32
80003e38:	00112e23          	sw	ra,28(sp)
80003e3c:	00812c23          	sw	s0,24(sp)
80003e40:	00912a23          	sw	s1,20(sp)
80003e44:	01212823          	sw	s2,16(sp)
80003e48:	01312623          	sw	s3,12(sp)
80003e4c:	02010413          	addi	s0,sp,32
80003e50:	00050913          	mv	s2,a0
80003e54:	00058993          	mv	s3,a1
  acquire(&bcache.lock);
80003e58:	00013517          	auipc	a0,0x13
80003e5c:	89850513          	addi	a0,a0,-1896 # 800166f0 <bcache>
80003e60:	ffffd097          	auipc	ra,0xffffd
80003e64:	09c080e7          	jalr	156(ra) # 80000efc <acquire>
  for(b = bcache.head.next; b != &bcache.head; b = b->next){
80003e68:	0001a497          	auipc	s1,0x1a
80003e6c:	7544a483          	lw	s1,1876(s1) # 8001e5bc <bcache+0x7ecc>
80003e70:	0001a797          	auipc	a5,0x1a
80003e74:	71c78793          	addi	a5,a5,1820 # 8001e58c <bcache+0x7e9c>
80003e78:	04f48863          	beq	s1,a5,80003ec8 <bread+0x94>
80003e7c:	00078713          	mv	a4,a5
80003e80:	00c0006f          	j	80003e8c <bread+0x58>
80003e84:	0304a483          	lw	s1,48(s1)
80003e88:	04e48063          	beq	s1,a4,80003ec8 <bread+0x94>
    if(b->dev == dev && b->blockno == blockno){
80003e8c:	0084a783          	lw	a5,8(s1)
80003e90:	fef91ae3          	bne	s2,a5,80003e84 <bread+0x50>
80003e94:	00c4a783          	lw	a5,12(s1)
80003e98:	fef996e3          	bne	s3,a5,80003e84 <bread+0x50>
      b->refcnt++;
80003e9c:	0284a783          	lw	a5,40(s1)
80003ea0:	00178793          	addi	a5,a5,1
80003ea4:	02f4a423          	sw	a5,40(s1)
      release(&bcache.lock);
80003ea8:	00013517          	auipc	a0,0x13
80003eac:	84850513          	addi	a0,a0,-1976 # 800166f0 <bcache>
80003eb0:	ffffd097          	auipc	ra,0xffffd
80003eb4:	0c0080e7          	jalr	192(ra) # 80000f70 <release>
      acquiresleep(&b->lock);
80003eb8:	01048513          	addi	a0,s1,16
80003ebc:	00002097          	auipc	ra,0x2
80003ec0:	bb0080e7          	jalr	-1104(ra) # 80005a6c <acquiresleep>
      return b;
80003ec4:	06c0006f          	j	80003f30 <bread+0xfc>
  for(b = bcache.head.prev; b != &bcache.head; b = b->prev){
80003ec8:	0001a497          	auipc	s1,0x1a
80003ecc:	6f04a483          	lw	s1,1776(s1) # 8001e5b8 <bcache+0x7ec8>
80003ed0:	0001a797          	auipc	a5,0x1a
80003ed4:	6bc78793          	addi	a5,a5,1724 # 8001e58c <bcache+0x7e9c>
80003ed8:	00f48c63          	beq	s1,a5,80003ef0 <bread+0xbc>
80003edc:	00078713          	mv	a4,a5
    if(b->refcnt == 0) {
80003ee0:	0284a783          	lw	a5,40(s1)
80003ee4:	00078e63          	beqz	a5,80003f00 <bread+0xcc>
  for(b = bcache.head.prev; b != &bcache.head; b = b->prev){
80003ee8:	02c4a483          	lw	s1,44(s1)
80003eec:	fee49ae3          	bne	s1,a4,80003ee0 <bread+0xac>
  panic("bget: no buffers");
80003ef0:	00005517          	auipc	a0,0x5
80003ef4:	5b050513          	addi	a0,a0,1456 # 800094a0 <userret+0x400>
80003ef8:	ffffd097          	auipc	ra,0xffffd
80003efc:	804080e7          	jalr	-2044(ra) # 800006fc <panic>
      b->dev = dev;
80003f00:	0124a423          	sw	s2,8(s1)
      b->blockno = blockno;
80003f04:	0134a623          	sw	s3,12(s1)
      b->valid = 0;
80003f08:	0004a023          	sw	zero,0(s1)
      b->refcnt = 1;
80003f0c:	00100793          	li	a5,1
80003f10:	02f4a423          	sw	a5,40(s1)
      release(&bcache.lock);
80003f14:	00012517          	auipc	a0,0x12
80003f18:	7dc50513          	addi	a0,a0,2012 # 800166f0 <bcache>
80003f1c:	ffffd097          	auipc	ra,0xffffd
80003f20:	054080e7          	jalr	84(ra) # 80000f70 <release>
      acquiresleep(&b->lock);
80003f24:	01048513          	addi	a0,s1,16
80003f28:	00002097          	auipc	ra,0x2
80003f2c:	b44080e7          	jalr	-1212(ra) # 80005a6c <acquiresleep>
  struct buf *b;

  b = bget(dev, blockno);
  if(!b->valid) {
80003f30:	0004a783          	lw	a5,0(s1)
80003f34:	02078263          	beqz	a5,80003f58 <bread+0x124>
    virtio_disk_rw(b, 0);
    b->valid = 1;
  }
  return b;
}
80003f38:	00048513          	mv	a0,s1
80003f3c:	01c12083          	lw	ra,28(sp)
80003f40:	01812403          	lw	s0,24(sp)
80003f44:	01412483          	lw	s1,20(sp)
80003f48:	01012903          	lw	s2,16(sp)
80003f4c:	00c12983          	lw	s3,12(sp)
80003f50:	02010113          	addi	sp,sp,32
80003f54:	00008067          	ret
    virtio_disk_rw(b, 0);
80003f58:	00000593          	li	a1,0
80003f5c:	00048513          	mv	a0,s1
80003f60:	00004097          	auipc	ra,0x4
80003f64:	27c080e7          	jalr	636(ra) # 800081dc <virtio_disk_rw>
    b->valid = 1;
80003f68:	00100793          	li	a5,1
80003f6c:	00f4a023          	sw	a5,0(s1)
  return b;
80003f70:	fc9ff06f          	j	80003f38 <bread+0x104>

80003f74 <bwrite>:

// Write b's contents to disk.  Must be locked.
void
bwrite(struct buf *b)
{
80003f74:	ff010113          	addi	sp,sp,-16
80003f78:	00112623          	sw	ra,12(sp)
80003f7c:	00812423          	sw	s0,8(sp)
80003f80:	00912223          	sw	s1,4(sp)
80003f84:	01010413          	addi	s0,sp,16
80003f88:	00050493          	mv	s1,a0
  if(!holdingsleep(&b->lock))
80003f8c:	01050513          	addi	a0,a0,16
80003f90:	00002097          	auipc	ra,0x2
80003f94:	bc8080e7          	jalr	-1080(ra) # 80005b58 <holdingsleep>
80003f98:	02050463          	beqz	a0,80003fc0 <bwrite+0x4c>
    panic("bwrite");
  virtio_disk_rw(b, 1);
80003f9c:	00100593          	li	a1,1
80003fa0:	00048513          	mv	a0,s1
80003fa4:	00004097          	auipc	ra,0x4
80003fa8:	238080e7          	jalr	568(ra) # 800081dc <virtio_disk_rw>
}
80003fac:	00c12083          	lw	ra,12(sp)
80003fb0:	00812403          	lw	s0,8(sp)
80003fb4:	00412483          	lw	s1,4(sp)
80003fb8:	01010113          	addi	sp,sp,16
80003fbc:	00008067          	ret
    panic("bwrite");
80003fc0:	00005517          	auipc	a0,0x5
80003fc4:	4f450513          	addi	a0,a0,1268 # 800094b4 <userret+0x414>
80003fc8:	ffffc097          	auipc	ra,0xffffc
80003fcc:	734080e7          	jalr	1844(ra) # 800006fc <panic>

80003fd0 <brelse>:

// Release a locked buffer.
// Move to the head of the MRU list.
void
brelse(struct buf *b)
{
80003fd0:	ff010113          	addi	sp,sp,-16
80003fd4:	00112623          	sw	ra,12(sp)
80003fd8:	00812423          	sw	s0,8(sp)
80003fdc:	00912223          	sw	s1,4(sp)
80003fe0:	01212023          	sw	s2,0(sp)
80003fe4:	01010413          	addi	s0,sp,16
80003fe8:	00050493          	mv	s1,a0
  if(!holdingsleep(&b->lock))
80003fec:	01050913          	addi	s2,a0,16
80003ff0:	00090513          	mv	a0,s2
80003ff4:	00002097          	auipc	ra,0x2
80003ff8:	b64080e7          	jalr	-1180(ra) # 80005b58 <holdingsleep>
80003ffc:	08050a63          	beqz	a0,80004090 <brelse+0xc0>
    panic("brelse");

  releasesleep(&b->lock);
80004000:	00090513          	mv	a0,s2
80004004:	00002097          	auipc	ra,0x2
80004008:	af0080e7          	jalr	-1296(ra) # 80005af4 <releasesleep>

  acquire(&bcache.lock);
8000400c:	00012517          	auipc	a0,0x12
80004010:	6e450513          	addi	a0,a0,1764 # 800166f0 <bcache>
80004014:	ffffd097          	auipc	ra,0xffffd
80004018:	ee8080e7          	jalr	-280(ra) # 80000efc <acquire>
  b->refcnt--;
8000401c:	0284a783          	lw	a5,40(s1)
80004020:	fff78793          	addi	a5,a5,-1
80004024:	02f4a423          	sw	a5,40(s1)
  if (b->refcnt == 0) {
80004028:	04079063          	bnez	a5,80004068 <brelse+0x98>
    // no one is waiting for it.
    b->next->prev = b->prev;
8000402c:	0304a703          	lw	a4,48(s1)
80004030:	02c4a783          	lw	a5,44(s1)
80004034:	02f72623          	sw	a5,44(a4)
    b->prev->next = b->next;
80004038:	0304a703          	lw	a4,48(s1)
8000403c:	02e7a823          	sw	a4,48(a5)
    b->next = bcache.head.next;
80004040:	0001a797          	auipc	a5,0x1a
80004044:	6b078793          	addi	a5,a5,1712 # 8001e6f0 <bcache+0x8000>
80004048:	ecc7a703          	lw	a4,-308(a5)
8000404c:	02e4a823          	sw	a4,48(s1)
    b->prev = &bcache.head;
80004050:	0001a717          	auipc	a4,0x1a
80004054:	53c70713          	addi	a4,a4,1340 # 8001e58c <bcache+0x7e9c>
80004058:	02e4a623          	sw	a4,44(s1)
    bcache.head.next->prev = b;
8000405c:	ecc7a703          	lw	a4,-308(a5)
80004060:	02972623          	sw	s1,44(a4)
    bcache.head.next = b;
80004064:	ec97a623          	sw	s1,-308(a5)
  }
  
  release(&bcache.lock);
80004068:	00012517          	auipc	a0,0x12
8000406c:	68850513          	addi	a0,a0,1672 # 800166f0 <bcache>
80004070:	ffffd097          	auipc	ra,0xffffd
80004074:	f00080e7          	jalr	-256(ra) # 80000f70 <release>
}
80004078:	00c12083          	lw	ra,12(sp)
8000407c:	00812403          	lw	s0,8(sp)
80004080:	00412483          	lw	s1,4(sp)
80004084:	00012903          	lw	s2,0(sp)
80004088:	01010113          	addi	sp,sp,16
8000408c:	00008067          	ret
    panic("brelse");
80004090:	00005517          	auipc	a0,0x5
80004094:	42c50513          	addi	a0,a0,1068 # 800094bc <userret+0x41c>
80004098:	ffffc097          	auipc	ra,0xffffc
8000409c:	664080e7          	jalr	1636(ra) # 800006fc <panic>

800040a0 <bpin>:

void
bpin(struct buf *b) {
800040a0:	ff010113          	addi	sp,sp,-16
800040a4:	00112623          	sw	ra,12(sp)
800040a8:	00812423          	sw	s0,8(sp)
800040ac:	00912223          	sw	s1,4(sp)
800040b0:	01010413          	addi	s0,sp,16
800040b4:	00050493          	mv	s1,a0
  acquire(&bcache.lock);
800040b8:	00012517          	auipc	a0,0x12
800040bc:	63850513          	addi	a0,a0,1592 # 800166f0 <bcache>
800040c0:	ffffd097          	auipc	ra,0xffffd
800040c4:	e3c080e7          	jalr	-452(ra) # 80000efc <acquire>
  b->refcnt++;
800040c8:	0284a783          	lw	a5,40(s1)
800040cc:	00178793          	addi	a5,a5,1
800040d0:	02f4a423          	sw	a5,40(s1)
  release(&bcache.lock);
800040d4:	00012517          	auipc	a0,0x12
800040d8:	61c50513          	addi	a0,a0,1564 # 800166f0 <bcache>
800040dc:	ffffd097          	auipc	ra,0xffffd
800040e0:	e94080e7          	jalr	-364(ra) # 80000f70 <release>
}
800040e4:	00c12083          	lw	ra,12(sp)
800040e8:	00812403          	lw	s0,8(sp)
800040ec:	00412483          	lw	s1,4(sp)
800040f0:	01010113          	addi	sp,sp,16
800040f4:	00008067          	ret

800040f8 <bunpin>:

void
bunpin(struct buf *b) {
800040f8:	ff010113          	addi	sp,sp,-16
800040fc:	00112623          	sw	ra,12(sp)
80004100:	00812423          	sw	s0,8(sp)
80004104:	00912223          	sw	s1,4(sp)
80004108:	01010413          	addi	s0,sp,16
8000410c:	00050493          	mv	s1,a0
  acquire(&bcache.lock);
80004110:	00012517          	auipc	a0,0x12
80004114:	5e050513          	addi	a0,a0,1504 # 800166f0 <bcache>
80004118:	ffffd097          	auipc	ra,0xffffd
8000411c:	de4080e7          	jalr	-540(ra) # 80000efc <acquire>
  b->refcnt--;
80004120:	0284a783          	lw	a5,40(s1)
80004124:	fff78793          	addi	a5,a5,-1
80004128:	02f4a423          	sw	a5,40(s1)
  release(&bcache.lock);
8000412c:	00012517          	auipc	a0,0x12
80004130:	5c450513          	addi	a0,a0,1476 # 800166f0 <bcache>
80004134:	ffffd097          	auipc	ra,0xffffd
80004138:	e3c080e7          	jalr	-452(ra) # 80000f70 <release>
}
8000413c:	00c12083          	lw	ra,12(sp)
80004140:	00812403          	lw	s0,8(sp)
80004144:	00412483          	lw	s1,4(sp)
80004148:	01010113          	addi	sp,sp,16
8000414c:	00008067          	ret

80004150 <bfree>:
}

// Free a disk block.
static void
bfree(int dev, uint b)
{
80004150:	ff010113          	addi	sp,sp,-16
80004154:	00112623          	sw	ra,12(sp)
80004158:	00812423          	sw	s0,8(sp)
8000415c:	00912223          	sw	s1,4(sp)
80004160:	01212023          	sw	s2,0(sp)
80004164:	01010413          	addi	s0,sp,16
80004168:	00058493          	mv	s1,a1
  struct buf *bp;
  int bi, m;

  bp = bread(dev, BBLOCK(b, sb));
8000416c:	00d5d593          	srli	a1,a1,0xd
80004170:	0001b797          	auipc	a5,0x1b
80004174:	8707a783          	lw	a5,-1936(a5) # 8001e9e0 <sb+0x1c>
80004178:	00f585b3          	add	a1,a1,a5
8000417c:	00000097          	auipc	ra,0x0
80004180:	cb8080e7          	jalr	-840(ra) # 80003e34 <bread>
  bi = b % BPB;
  m = 1 << (bi % 8);
80004184:	0074f713          	andi	a4,s1,7
80004188:	00100793          	li	a5,1
8000418c:	00e797b3          	sll	a5,a5,a4
  bi = b % BPB;
80004190:	01349493          	slli	s1,s1,0x13
  if((bp->data[bi/8] & m) == 0)
80004194:	0164d493          	srli	s1,s1,0x16
80004198:	00950733          	add	a4,a0,s1
8000419c:	03874703          	lbu	a4,56(a4)
800041a0:	00f776b3          	and	a3,a4,a5
800041a4:	04068263          	beqz	a3,800041e8 <bfree+0x98>
800041a8:	00050913          	mv	s2,a0
    panic("freeing free block");
  bp->data[bi/8] &= ~m;
800041ac:	009504b3          	add	s1,a0,s1
800041b0:	fff7c793          	not	a5,a5
800041b4:	00f77733          	and	a4,a4,a5
800041b8:	02e48c23          	sb	a4,56(s1)
  log_write(bp);
800041bc:	00001097          	auipc	ra,0x1
800041c0:	72c080e7          	jalr	1836(ra) # 800058e8 <log_write>
  brelse(bp);
800041c4:	00090513          	mv	a0,s2
800041c8:	00000097          	auipc	ra,0x0
800041cc:	e08080e7          	jalr	-504(ra) # 80003fd0 <brelse>
}
800041d0:	00c12083          	lw	ra,12(sp)
800041d4:	00812403          	lw	s0,8(sp)
800041d8:	00412483          	lw	s1,4(sp)
800041dc:	00012903          	lw	s2,0(sp)
800041e0:	01010113          	addi	sp,sp,16
800041e4:	00008067          	ret
    panic("freeing free block");
800041e8:	00005517          	auipc	a0,0x5
800041ec:	2dc50513          	addi	a0,a0,732 # 800094c4 <userret+0x424>
800041f0:	ffffc097          	auipc	ra,0xffffc
800041f4:	50c080e7          	jalr	1292(ra) # 800006fc <panic>

800041f8 <balloc>:
{
800041f8:	fd010113          	addi	sp,sp,-48
800041fc:	02112623          	sw	ra,44(sp)
80004200:	02812423          	sw	s0,40(sp)
80004204:	02912223          	sw	s1,36(sp)
80004208:	03212023          	sw	s2,32(sp)
8000420c:	01312e23          	sw	s3,28(sp)
80004210:	01412c23          	sw	s4,24(sp)
80004214:	01512a23          	sw	s5,20(sp)
80004218:	01612823          	sw	s6,16(sp)
8000421c:	01712623          	sw	s7,12(sp)
80004220:	03010413          	addi	s0,sp,48
  for(b = 0; b < sb.size; b += BPB){
80004224:	0001a797          	auipc	a5,0x1a
80004228:	7a47a783          	lw	a5,1956(a5) # 8001e9c8 <sb+0x4>
8000422c:	08078e63          	beqz	a5,800042c8 <balloc+0xd0>
80004230:	00050b13          	mv	s6,a0
80004234:	00000a93          	li	s5,0
    bp = bread(dev, BBLOCK(b, sb));
80004238:	0001ab97          	auipc	s7,0x1a
8000423c:	78cb8b93          	addi	s7,s7,1932 # 8001e9c4 <sb>
      m = 1 << (bi % 8);
80004240:	00100a13          	li	s4,1
    for(bi = 0; bi < BPB && b + bi < sb.size; bi++){
80004244:	000029b7          	lui	s3,0x2
80004248:	01c0006f          	j	80004264 <balloc+0x6c>
    brelse(bp);
8000424c:	00090513          	mv	a0,s2
80004250:	00000097          	auipc	ra,0x0
80004254:	d80080e7          	jalr	-640(ra) # 80003fd0 <brelse>
  for(b = 0; b < sb.size; b += BPB){
80004258:	013a8ab3          	add	s5,s5,s3
8000425c:	004ba783          	lw	a5,4(s7)
80004260:	06faf463          	bgeu	s5,a5,800042c8 <balloc+0xd0>
    bp = bread(dev, BBLOCK(b, sb));
80004264:	40dad593          	srai	a1,s5,0xd
80004268:	01cba783          	lw	a5,28(s7)
8000426c:	00f585b3          	add	a1,a1,a5
80004270:	000b0513          	mv	a0,s6
80004274:	00000097          	auipc	ra,0x0
80004278:	bc0080e7          	jalr	-1088(ra) # 80003e34 <bread>
8000427c:	00050913          	mv	s2,a0
    for(bi = 0; bi < BPB && b + bi < sb.size; bi++){
80004280:	004ba503          	lw	a0,4(s7)
80004284:	000a8493          	mv	s1,s5
80004288:	00000713          	li	a4,0
8000428c:	fca4f0e3          	bgeu	s1,a0,8000424c <balloc+0x54>
      m = 1 << (bi % 8);
80004290:	00777693          	andi	a3,a4,7
80004294:	00da16b3          	sll	a3,s4,a3
      if((bp->data[bi/8] & m) == 0){  // Is block free?
80004298:	41f75793          	srai	a5,a4,0x1f
8000429c:	0077f793          	andi	a5,a5,7
800042a0:	00e787b3          	add	a5,a5,a4
800042a4:	4037d793          	srai	a5,a5,0x3
800042a8:	00f90633          	add	a2,s2,a5
800042ac:	03864603          	lbu	a2,56(a2)
800042b0:	00d675b3          	and	a1,a2,a3
800042b4:	02058263          	beqz	a1,800042d8 <balloc+0xe0>
    for(bi = 0; bi < BPB && b + bi < sb.size; bi++){
800042b8:	00170713          	addi	a4,a4,1
800042bc:	00148493          	addi	s1,s1,1
800042c0:	fd3716e3          	bne	a4,s3,8000428c <balloc+0x94>
800042c4:	f89ff06f          	j	8000424c <balloc+0x54>
  panic("balloc: out of blocks");
800042c8:	00005517          	auipc	a0,0x5
800042cc:	21050513          	addi	a0,a0,528 # 800094d8 <userret+0x438>
800042d0:	ffffc097          	auipc	ra,0xffffc
800042d4:	42c080e7          	jalr	1068(ra) # 800006fc <panic>
        bp->data[bi/8] |= m;  // Mark block in use.
800042d8:	00f907b3          	add	a5,s2,a5
800042dc:	00d66633          	or	a2,a2,a3
800042e0:	02c78c23          	sb	a2,56(a5)
        log_write(bp);
800042e4:	00090513          	mv	a0,s2
800042e8:	00001097          	auipc	ra,0x1
800042ec:	600080e7          	jalr	1536(ra) # 800058e8 <log_write>
        brelse(bp);
800042f0:	00090513          	mv	a0,s2
800042f4:	00000097          	auipc	ra,0x0
800042f8:	cdc080e7          	jalr	-804(ra) # 80003fd0 <brelse>
  bp = bread(dev, bno);
800042fc:	00048593          	mv	a1,s1
80004300:	000b0513          	mv	a0,s6
80004304:	00000097          	auipc	ra,0x0
80004308:	b30080e7          	jalr	-1232(ra) # 80003e34 <bread>
8000430c:	00050913          	mv	s2,a0
  memset(bp->data, 0, BSIZE);
80004310:	40000613          	li	a2,1024
80004314:	00000593          	li	a1,0
80004318:	03850513          	addi	a0,a0,56
8000431c:	ffffd097          	auipc	ra,0xffffd
80004320:	cb4080e7          	jalr	-844(ra) # 80000fd0 <memset>
  log_write(bp);
80004324:	00090513          	mv	a0,s2
80004328:	00001097          	auipc	ra,0x1
8000432c:	5c0080e7          	jalr	1472(ra) # 800058e8 <log_write>
  brelse(bp);
80004330:	00090513          	mv	a0,s2
80004334:	00000097          	auipc	ra,0x0
80004338:	c9c080e7          	jalr	-868(ra) # 80003fd0 <brelse>
}
8000433c:	00048513          	mv	a0,s1
80004340:	02c12083          	lw	ra,44(sp)
80004344:	02812403          	lw	s0,40(sp)
80004348:	02412483          	lw	s1,36(sp)
8000434c:	02012903          	lw	s2,32(sp)
80004350:	01c12983          	lw	s3,28(sp)
80004354:	01812a03          	lw	s4,24(sp)
80004358:	01412a83          	lw	s5,20(sp)
8000435c:	01012b03          	lw	s6,16(sp)
80004360:	00c12b83          	lw	s7,12(sp)
80004364:	03010113          	addi	sp,sp,48
80004368:	00008067          	ret

8000436c <bmap>:

// Return the disk block address of the nth block in inode ip.
// If there is no such block, bmap allocates one.
static uint
bmap(struct inode *ip, uint bn)
{
8000436c:	fe010113          	addi	sp,sp,-32
80004370:	00112e23          	sw	ra,28(sp)
80004374:	00812c23          	sw	s0,24(sp)
80004378:	00912a23          	sw	s1,20(sp)
8000437c:	01212823          	sw	s2,16(sp)
80004380:	01312623          	sw	s3,12(sp)
80004384:	02010413          	addi	s0,sp,32
80004388:	00050913          	mv	s2,a0
  uint addr, *a;
  struct buf *bp;

  if(bn < NDIRECT){
8000438c:	00b00793          	li	a5,11
80004390:	06b7f863          	bgeu	a5,a1,80004400 <bmap+0x94>
80004394:	01412423          	sw	s4,8(sp)
    if((addr = ip->addrs[bn]) == 0)
      ip->addrs[bn] = addr = balloc(ip->dev);
    return addr;
  }
  bn -= NDIRECT;
80004398:	ff458493          	addi	s1,a1,-12

  if(bn < NINDIRECT){
8000439c:	0ff00793          	li	a5,255
800043a0:	0c97e263          	bltu	a5,s1,80004464 <bmap+0xf8>
    // Load indirect block, allocating if necessary.
    if((addr = ip->addrs[NDIRECT]) == 0)
800043a4:	06452583          	lw	a1,100(a0)
800043a8:	08058063          	beqz	a1,80004428 <bmap+0xbc>
      ip->addrs[NDIRECT] = addr = balloc(ip->dev);
    bp = bread(ip->dev, addr);
800043ac:	00092503          	lw	a0,0(s2)
800043b0:	00000097          	auipc	ra,0x0
800043b4:	a84080e7          	jalr	-1404(ra) # 80003e34 <bread>
800043b8:	00050a13          	mv	s4,a0
    a = (uint*)bp->data;
800043bc:	03850793          	addi	a5,a0,56
    if((addr = a[bn]) == 0){
800043c0:	00249593          	slli	a1,s1,0x2
800043c4:	00b784b3          	add	s1,a5,a1
800043c8:	0004a983          	lw	s3,0(s1)
800043cc:	06098a63          	beqz	s3,80004440 <bmap+0xd4>
      a[bn] = addr = balloc(ip->dev);
      log_write(bp);
    }
    brelse(bp);
800043d0:	000a0513          	mv	a0,s4
800043d4:	00000097          	auipc	ra,0x0
800043d8:	bfc080e7          	jalr	-1028(ra) # 80003fd0 <brelse>
    return addr;
800043dc:	00812a03          	lw	s4,8(sp)
  }

  panic("bmap: out of range");
}
800043e0:	00098513          	mv	a0,s3
800043e4:	01c12083          	lw	ra,28(sp)
800043e8:	01812403          	lw	s0,24(sp)
800043ec:	01412483          	lw	s1,20(sp)
800043f0:	01012903          	lw	s2,16(sp)
800043f4:	00c12983          	lw	s3,12(sp)
800043f8:	02010113          	addi	sp,sp,32
800043fc:	00008067          	ret
    if((addr = ip->addrs[bn]) == 0)
80004400:	00259593          	slli	a1,a1,0x2
80004404:	00b504b3          	add	s1,a0,a1
80004408:	0344a983          	lw	s3,52(s1)
8000440c:	fc099ae3          	bnez	s3,800043e0 <bmap+0x74>
      ip->addrs[bn] = addr = balloc(ip->dev);
80004410:	00052503          	lw	a0,0(a0)
80004414:	00000097          	auipc	ra,0x0
80004418:	de4080e7          	jalr	-540(ra) # 800041f8 <balloc>
8000441c:	00050993          	mv	s3,a0
80004420:	02a4aa23          	sw	a0,52(s1)
80004424:	fbdff06f          	j	800043e0 <bmap+0x74>
      ip->addrs[NDIRECT] = addr = balloc(ip->dev);
80004428:	00052503          	lw	a0,0(a0)
8000442c:	00000097          	auipc	ra,0x0
80004430:	dcc080e7          	jalr	-564(ra) # 800041f8 <balloc>
80004434:	00050593          	mv	a1,a0
80004438:	06a92223          	sw	a0,100(s2)
8000443c:	f71ff06f          	j	800043ac <bmap+0x40>
      a[bn] = addr = balloc(ip->dev);
80004440:	00092503          	lw	a0,0(s2)
80004444:	00000097          	auipc	ra,0x0
80004448:	db4080e7          	jalr	-588(ra) # 800041f8 <balloc>
8000444c:	00050993          	mv	s3,a0
80004450:	00a4a023          	sw	a0,0(s1)
      log_write(bp);
80004454:	000a0513          	mv	a0,s4
80004458:	00001097          	auipc	ra,0x1
8000445c:	490080e7          	jalr	1168(ra) # 800058e8 <log_write>
80004460:	f71ff06f          	j	800043d0 <bmap+0x64>
  panic("bmap: out of range");
80004464:	00005517          	auipc	a0,0x5
80004468:	08c50513          	addi	a0,a0,140 # 800094f0 <userret+0x450>
8000446c:	ffffc097          	auipc	ra,0xffffc
80004470:	290080e7          	jalr	656(ra) # 800006fc <panic>

80004474 <iget>:
{
80004474:	fe010113          	addi	sp,sp,-32
80004478:	00112e23          	sw	ra,28(sp)
8000447c:	00812c23          	sw	s0,24(sp)
80004480:	00912a23          	sw	s1,20(sp)
80004484:	01212823          	sw	s2,16(sp)
80004488:	01312623          	sw	s3,12(sp)
8000448c:	01412423          	sw	s4,8(sp)
80004490:	02010413          	addi	s0,sp,32
80004494:	00050993          	mv	s3,a0
80004498:	00058a13          	mv	s4,a1
  acquire(&icache.lock);
8000449c:	0001a517          	auipc	a0,0x1a
800044a0:	54850513          	addi	a0,a0,1352 # 8001e9e4 <icache>
800044a4:	ffffd097          	auipc	ra,0xffffd
800044a8:	a58080e7          	jalr	-1448(ra) # 80000efc <acquire>
  empty = 0;
800044ac:	00000913          	li	s2,0
  for(ip = &icache.inode[0]; ip < &icache.inode[NINODE]; ip++){
800044b0:	0001a497          	auipc	s1,0x1a
800044b4:	54048493          	addi	s1,s1,1344 # 8001e9f0 <icache+0xc>
800044b8:	0001c697          	auipc	a3,0x1c
800044bc:	98868693          	addi	a3,a3,-1656 # 8001fe40 <log>
800044c0:	0140006f          	j	800044d4 <iget+0x60>
    if(empty == 0 && ip->ref == 0)    // Remember empty slot.
800044c4:	00f967b3          	or	a5,s2,a5
800044c8:	04078263          	beqz	a5,8000450c <iget+0x98>
  for(ip = &icache.inode[0]; ip < &icache.inode[NINODE]; ip++){
800044cc:	06848493          	addi	s1,s1,104
800044d0:	04d48263          	beq	s1,a3,80004514 <iget+0xa0>
    if(ip->ref > 0 && ip->dev == dev && ip->inum == inum){
800044d4:	0084a783          	lw	a5,8(s1)
800044d8:	fef056e3          	blez	a5,800044c4 <iget+0x50>
800044dc:	0004a703          	lw	a4,0(s1)
800044e0:	ff3716e3          	bne	a4,s3,800044cc <iget+0x58>
800044e4:	0044a703          	lw	a4,4(s1)
800044e8:	ff4712e3          	bne	a4,s4,800044cc <iget+0x58>
      ip->ref++;
800044ec:	00178793          	addi	a5,a5,1
800044f0:	00f4a423          	sw	a5,8(s1)
      release(&icache.lock);
800044f4:	0001a517          	auipc	a0,0x1a
800044f8:	4f050513          	addi	a0,a0,1264 # 8001e9e4 <icache>
800044fc:	ffffd097          	auipc	ra,0xffffd
80004500:	a74080e7          	jalr	-1420(ra) # 80000f70 <release>
      return ip;
80004504:	00048913          	mv	s2,s1
80004508:	0340006f          	j	8000453c <iget+0xc8>
      empty = ip;
8000450c:	00048913          	mv	s2,s1
80004510:	fbdff06f          	j	800044cc <iget+0x58>
  if(empty == 0)
80004514:	04090663          	beqz	s2,80004560 <iget+0xec>
  ip->dev = dev;
80004518:	01392023          	sw	s3,0(s2)
  ip->inum = inum;
8000451c:	01492223          	sw	s4,4(s2)
  ip->ref = 1;
80004520:	00100793          	li	a5,1
80004524:	00f92423          	sw	a5,8(s2)
  ip->valid = 0;
80004528:	02092223          	sw	zero,36(s2)
  release(&icache.lock);
8000452c:	0001a517          	auipc	a0,0x1a
80004530:	4b850513          	addi	a0,a0,1208 # 8001e9e4 <icache>
80004534:	ffffd097          	auipc	ra,0xffffd
80004538:	a3c080e7          	jalr	-1476(ra) # 80000f70 <release>
}
8000453c:	00090513          	mv	a0,s2
80004540:	01c12083          	lw	ra,28(sp)
80004544:	01812403          	lw	s0,24(sp)
80004548:	01412483          	lw	s1,20(sp)
8000454c:	01012903          	lw	s2,16(sp)
80004550:	00c12983          	lw	s3,12(sp)
80004554:	00812a03          	lw	s4,8(sp)
80004558:	02010113          	addi	sp,sp,32
8000455c:	00008067          	ret
    panic("iget: no inodes");
80004560:	00005517          	auipc	a0,0x5
80004564:	fa450513          	addi	a0,a0,-92 # 80009504 <userret+0x464>
80004568:	ffffc097          	auipc	ra,0xffffc
8000456c:	194080e7          	jalr	404(ra) # 800006fc <panic>

80004570 <fsinit>:
fsinit(int dev) {
80004570:	ff010113          	addi	sp,sp,-16
80004574:	00112623          	sw	ra,12(sp)
80004578:	00812423          	sw	s0,8(sp)
8000457c:	00912223          	sw	s1,4(sp)
80004580:	01212023          	sw	s2,0(sp)
80004584:	01010413          	addi	s0,sp,16
80004588:	00050913          	mv	s2,a0
  bp = bread(dev, 1);
8000458c:	00100593          	li	a1,1
80004590:	00000097          	auipc	ra,0x0
80004594:	8a4080e7          	jalr	-1884(ra) # 80003e34 <bread>
80004598:	00050493          	mv	s1,a0
  memmove(sb, bp->data, sizeof(*sb));
8000459c:	02000613          	li	a2,32
800045a0:	03850593          	addi	a1,a0,56
800045a4:	0001a517          	auipc	a0,0x1a
800045a8:	42050513          	addi	a0,a0,1056 # 8001e9c4 <sb>
800045ac:	ffffd097          	auipc	ra,0xffffd
800045b0:	ab0080e7          	jalr	-1360(ra) # 8000105c <memmove>
  brelse(bp);
800045b4:	00048513          	mv	a0,s1
800045b8:	00000097          	auipc	ra,0x0
800045bc:	a18080e7          	jalr	-1512(ra) # 80003fd0 <brelse>
  if(sb.magic != FSMAGIC)
800045c0:	0001a717          	auipc	a4,0x1a
800045c4:	40472703          	lw	a4,1028(a4) # 8001e9c4 <sb>
800045c8:	102037b7          	lui	a5,0x10203
800045cc:	04078793          	addi	a5,a5,64 # 10203040 <_entry-0x6fdfcfc0>
800045d0:	02f71863          	bne	a4,a5,80004600 <fsinit+0x90>
  initlog(dev, &sb);
800045d4:	0001a597          	auipc	a1,0x1a
800045d8:	3f058593          	addi	a1,a1,1008 # 8001e9c4 <sb>
800045dc:	00090513          	mv	a0,s2
800045e0:	00001097          	auipc	ra,0x1
800045e4:	fc8080e7          	jalr	-56(ra) # 800055a8 <initlog>
}
800045e8:	00c12083          	lw	ra,12(sp)
800045ec:	00812403          	lw	s0,8(sp)
800045f0:	00412483          	lw	s1,4(sp)
800045f4:	00012903          	lw	s2,0(sp)
800045f8:	01010113          	addi	sp,sp,16
800045fc:	00008067          	ret
    panic("invalid file system");
80004600:	00005517          	auipc	a0,0x5
80004604:	f1450513          	addi	a0,a0,-236 # 80009514 <userret+0x474>
80004608:	ffffc097          	auipc	ra,0xffffc
8000460c:	0f4080e7          	jalr	244(ra) # 800006fc <panic>

80004610 <iinit>:
{
80004610:	fe010113          	addi	sp,sp,-32
80004614:	00112e23          	sw	ra,28(sp)
80004618:	00812c23          	sw	s0,24(sp)
8000461c:	00912a23          	sw	s1,20(sp)
80004620:	01212823          	sw	s2,16(sp)
80004624:	01312623          	sw	s3,12(sp)
80004628:	02010413          	addi	s0,sp,32
  initlock(&icache.lock, "icache");
8000462c:	00005597          	auipc	a1,0x5
80004630:	efc58593          	addi	a1,a1,-260 # 80009528 <userret+0x488>
80004634:	0001a517          	auipc	a0,0x1a
80004638:	3b050513          	addi	a0,a0,944 # 8001e9e4 <icache>
8000463c:	ffffc097          	auipc	ra,0xffffc
80004640:	730080e7          	jalr	1840(ra) # 80000d6c <initlock>
  for(i = 0; i < NINODE; i++) {
80004644:	0001a497          	auipc	s1,0x1a
80004648:	3b848493          	addi	s1,s1,952 # 8001e9fc <icache+0x18>
8000464c:	0001c997          	auipc	s3,0x1c
80004650:	80098993          	addi	s3,s3,-2048 # 8001fe4c <log+0xc>
    initsleeplock(&icache.inode[i].lock, "inode");
80004654:	00005917          	auipc	s2,0x5
80004658:	edc90913          	addi	s2,s2,-292 # 80009530 <userret+0x490>
8000465c:	00090593          	mv	a1,s2
80004660:	00048513          	mv	a0,s1
80004664:	00001097          	auipc	ra,0x1
80004668:	3b0080e7          	jalr	944(ra) # 80005a14 <initsleeplock>
  for(i = 0; i < NINODE; i++) {
8000466c:	06848493          	addi	s1,s1,104
80004670:	ff3496e3          	bne	s1,s3,8000465c <iinit+0x4c>
}
80004674:	01c12083          	lw	ra,28(sp)
80004678:	01812403          	lw	s0,24(sp)
8000467c:	01412483          	lw	s1,20(sp)
80004680:	01012903          	lw	s2,16(sp)
80004684:	00c12983          	lw	s3,12(sp)
80004688:	02010113          	addi	sp,sp,32
8000468c:	00008067          	ret

80004690 <ialloc>:
{
80004690:	fe010113          	addi	sp,sp,-32
80004694:	00112e23          	sw	ra,28(sp)
80004698:	00812c23          	sw	s0,24(sp)
8000469c:	00912a23          	sw	s1,20(sp)
800046a0:	01212823          	sw	s2,16(sp)
800046a4:	01312623          	sw	s3,12(sp)
800046a8:	01412423          	sw	s4,8(sp)
800046ac:	01512223          	sw	s5,4(sp)
800046b0:	01612023          	sw	s6,0(sp)
800046b4:	02010413          	addi	s0,sp,32
  for(inum = 1; inum < sb.ninodes; inum++){
800046b8:	0001a717          	auipc	a4,0x1a
800046bc:	31872703          	lw	a4,792(a4) # 8001e9d0 <sb+0xc>
800046c0:	00100793          	li	a5,1
800046c4:	06e7f063          	bgeu	a5,a4,80004724 <ialloc+0x94>
800046c8:	00050a93          	mv	s5,a0
800046cc:	00058b13          	mv	s6,a1
800046d0:	00078913          	mv	s2,a5
    bp = bread(dev, IBLOCK(inum, sb));
800046d4:	0001aa17          	auipc	s4,0x1a
800046d8:	2f0a0a13          	addi	s4,s4,752 # 8001e9c4 <sb>
800046dc:	00495593          	srli	a1,s2,0x4
800046e0:	018a2783          	lw	a5,24(s4)
800046e4:	00f585b3          	add	a1,a1,a5
800046e8:	000a8513          	mv	a0,s5
800046ec:	fffff097          	auipc	ra,0xfffff
800046f0:	748080e7          	jalr	1864(ra) # 80003e34 <bread>
800046f4:	00050493          	mv	s1,a0
    dip = (struct dinode*)bp->data + inum%IPB;
800046f8:	03850993          	addi	s3,a0,56
800046fc:	00f97793          	andi	a5,s2,15
80004700:	00679793          	slli	a5,a5,0x6
80004704:	00f989b3          	add	s3,s3,a5
    if(dip->type == 0){  // a free inode
80004708:	00099783          	lh	a5,0(s3)
8000470c:	02078463          	beqz	a5,80004734 <ialloc+0xa4>
    brelse(bp);
80004710:	00000097          	auipc	ra,0x0
80004714:	8c0080e7          	jalr	-1856(ra) # 80003fd0 <brelse>
  for(inum = 1; inum < sb.ninodes; inum++){
80004718:	00190913          	addi	s2,s2,1
8000471c:	00ca2783          	lw	a5,12(s4)
80004720:	faf96ee3          	bltu	s2,a5,800046dc <ialloc+0x4c>
  panic("ialloc: no inodes");
80004724:	00005517          	auipc	a0,0x5
80004728:	e1450513          	addi	a0,a0,-492 # 80009538 <userret+0x498>
8000472c:	ffffc097          	auipc	ra,0xffffc
80004730:	fd0080e7          	jalr	-48(ra) # 800006fc <panic>
      memset(dip, 0, sizeof(*dip));
80004734:	04000613          	li	a2,64
80004738:	00000593          	li	a1,0
8000473c:	00098513          	mv	a0,s3
80004740:	ffffd097          	auipc	ra,0xffffd
80004744:	890080e7          	jalr	-1904(ra) # 80000fd0 <memset>
      dip->type = type;
80004748:	01699023          	sh	s6,0(s3)
      log_write(bp);   // mark it allocated on the disk
8000474c:	00048513          	mv	a0,s1
80004750:	00001097          	auipc	ra,0x1
80004754:	198080e7          	jalr	408(ra) # 800058e8 <log_write>
      brelse(bp);
80004758:	00048513          	mv	a0,s1
8000475c:	00000097          	auipc	ra,0x0
80004760:	874080e7          	jalr	-1932(ra) # 80003fd0 <brelse>
      return iget(dev, inum);
80004764:	00090593          	mv	a1,s2
80004768:	000a8513          	mv	a0,s5
8000476c:	00000097          	auipc	ra,0x0
80004770:	d08080e7          	jalr	-760(ra) # 80004474 <iget>
}
80004774:	01c12083          	lw	ra,28(sp)
80004778:	01812403          	lw	s0,24(sp)
8000477c:	01412483          	lw	s1,20(sp)
80004780:	01012903          	lw	s2,16(sp)
80004784:	00c12983          	lw	s3,12(sp)
80004788:	00812a03          	lw	s4,8(sp)
8000478c:	00412a83          	lw	s5,4(sp)
80004790:	00012b03          	lw	s6,0(sp)
80004794:	02010113          	addi	sp,sp,32
80004798:	00008067          	ret

8000479c <iupdate>:
{
8000479c:	ff010113          	addi	sp,sp,-16
800047a0:	00112623          	sw	ra,12(sp)
800047a4:	00812423          	sw	s0,8(sp)
800047a8:	00912223          	sw	s1,4(sp)
800047ac:	01212023          	sw	s2,0(sp)
800047b0:	01010413          	addi	s0,sp,16
800047b4:	00050493          	mv	s1,a0
  bp = bread(ip->dev, IBLOCK(ip->inum, sb));
800047b8:	00452783          	lw	a5,4(a0)
800047bc:	0047d793          	srli	a5,a5,0x4
800047c0:	0001a597          	auipc	a1,0x1a
800047c4:	21c5a583          	lw	a1,540(a1) # 8001e9dc <sb+0x18>
800047c8:	00b785b3          	add	a1,a5,a1
800047cc:	00052503          	lw	a0,0(a0)
800047d0:	fffff097          	auipc	ra,0xfffff
800047d4:	664080e7          	jalr	1636(ra) # 80003e34 <bread>
800047d8:	00050913          	mv	s2,a0
  dip = (struct dinode*)bp->data + ip->inum%IPB;
800047dc:	03850793          	addi	a5,a0,56
800047e0:	0044a703          	lw	a4,4(s1)
800047e4:	00f77713          	andi	a4,a4,15
800047e8:	00671713          	slli	a4,a4,0x6
800047ec:	00e787b3          	add	a5,a5,a4
  dip->type = ip->type;
800047f0:	02849703          	lh	a4,40(s1)
800047f4:	00e79023          	sh	a4,0(a5)
  dip->major = ip->major;
800047f8:	02a49703          	lh	a4,42(s1)
800047fc:	00e79123          	sh	a4,2(a5)
  dip->minor = ip->minor;
80004800:	02c49703          	lh	a4,44(s1)
80004804:	00e79223          	sh	a4,4(a5)
  dip->nlink = ip->nlink;
80004808:	02e49703          	lh	a4,46(s1)
8000480c:	00e79323          	sh	a4,6(a5)
  dip->size = ip->size;
80004810:	0304a703          	lw	a4,48(s1)
80004814:	00e7a423          	sw	a4,8(a5)
  memmove(dip->addrs, ip->addrs, sizeof(ip->addrs));
80004818:	03400613          	li	a2,52
8000481c:	00c485b3          	add	a1,s1,a2
80004820:	00c78513          	addi	a0,a5,12
80004824:	ffffd097          	auipc	ra,0xffffd
80004828:	838080e7          	jalr	-1992(ra) # 8000105c <memmove>
  log_write(bp);
8000482c:	00090513          	mv	a0,s2
80004830:	00001097          	auipc	ra,0x1
80004834:	0b8080e7          	jalr	184(ra) # 800058e8 <log_write>
  brelse(bp);
80004838:	00090513          	mv	a0,s2
8000483c:	fffff097          	auipc	ra,0xfffff
80004840:	794080e7          	jalr	1940(ra) # 80003fd0 <brelse>
}
80004844:	00c12083          	lw	ra,12(sp)
80004848:	00812403          	lw	s0,8(sp)
8000484c:	00412483          	lw	s1,4(sp)
80004850:	00012903          	lw	s2,0(sp)
80004854:	01010113          	addi	sp,sp,16
80004858:	00008067          	ret

8000485c <idup>:
{
8000485c:	ff010113          	addi	sp,sp,-16
80004860:	00112623          	sw	ra,12(sp)
80004864:	00812423          	sw	s0,8(sp)
80004868:	00912223          	sw	s1,4(sp)
8000486c:	01010413          	addi	s0,sp,16
80004870:	00050493          	mv	s1,a0
  acquire(&icache.lock);
80004874:	0001a517          	auipc	a0,0x1a
80004878:	17050513          	addi	a0,a0,368 # 8001e9e4 <icache>
8000487c:	ffffc097          	auipc	ra,0xffffc
80004880:	680080e7          	jalr	1664(ra) # 80000efc <acquire>
  ip->ref++;
80004884:	0084a783          	lw	a5,8(s1)
80004888:	00178793          	addi	a5,a5,1
8000488c:	00f4a423          	sw	a5,8(s1)
  release(&icache.lock);
80004890:	0001a517          	auipc	a0,0x1a
80004894:	15450513          	addi	a0,a0,340 # 8001e9e4 <icache>
80004898:	ffffc097          	auipc	ra,0xffffc
8000489c:	6d8080e7          	jalr	1752(ra) # 80000f70 <release>
}
800048a0:	00048513          	mv	a0,s1
800048a4:	00c12083          	lw	ra,12(sp)
800048a8:	00812403          	lw	s0,8(sp)
800048ac:	00412483          	lw	s1,4(sp)
800048b0:	01010113          	addi	sp,sp,16
800048b4:	00008067          	ret

800048b8 <ilock>:
{
800048b8:	ff010113          	addi	sp,sp,-16
800048bc:	00112623          	sw	ra,12(sp)
800048c0:	00812423          	sw	s0,8(sp)
800048c4:	00912223          	sw	s1,4(sp)
800048c8:	01010413          	addi	s0,sp,16
  if(ip == 0 || ip->ref < 1)
800048cc:	02050c63          	beqz	a0,80004904 <ilock+0x4c>
800048d0:	00050493          	mv	s1,a0
800048d4:	00852783          	lw	a5,8(a0)
800048d8:	02f05663          	blez	a5,80004904 <ilock+0x4c>
  acquiresleep(&ip->lock);
800048dc:	00c50513          	addi	a0,a0,12
800048e0:	00001097          	auipc	ra,0x1
800048e4:	18c080e7          	jalr	396(ra) # 80005a6c <acquiresleep>
  if(ip->valid == 0){
800048e8:	0244a783          	lw	a5,36(s1)
800048ec:	02078663          	beqz	a5,80004918 <ilock+0x60>
}
800048f0:	00c12083          	lw	ra,12(sp)
800048f4:	00812403          	lw	s0,8(sp)
800048f8:	00412483          	lw	s1,4(sp)
800048fc:	01010113          	addi	sp,sp,16
80004900:	00008067          	ret
80004904:	01212023          	sw	s2,0(sp)
    panic("ilock");
80004908:	00005517          	auipc	a0,0x5
8000490c:	c4450513          	addi	a0,a0,-956 # 8000954c <userret+0x4ac>
80004910:	ffffc097          	auipc	ra,0xffffc
80004914:	dec080e7          	jalr	-532(ra) # 800006fc <panic>
80004918:	01212023          	sw	s2,0(sp)
    bp = bread(ip->dev, IBLOCK(ip->inum, sb));
8000491c:	0044a783          	lw	a5,4(s1)
80004920:	0047d793          	srli	a5,a5,0x4
80004924:	0001a597          	auipc	a1,0x1a
80004928:	0b85a583          	lw	a1,184(a1) # 8001e9dc <sb+0x18>
8000492c:	00b785b3          	add	a1,a5,a1
80004930:	0004a503          	lw	a0,0(s1)
80004934:	fffff097          	auipc	ra,0xfffff
80004938:	500080e7          	jalr	1280(ra) # 80003e34 <bread>
8000493c:	00050913          	mv	s2,a0
    dip = (struct dinode*)bp->data + ip->inum%IPB;
80004940:	03850593          	addi	a1,a0,56
80004944:	0044a783          	lw	a5,4(s1)
80004948:	00f7f793          	andi	a5,a5,15
8000494c:	00679793          	slli	a5,a5,0x6
80004950:	00f585b3          	add	a1,a1,a5
    ip->type = dip->type;
80004954:	00059783          	lh	a5,0(a1)
80004958:	02f49423          	sh	a5,40(s1)
    ip->major = dip->major;
8000495c:	00259783          	lh	a5,2(a1)
80004960:	02f49523          	sh	a5,42(s1)
    ip->minor = dip->minor;
80004964:	00459783          	lh	a5,4(a1)
80004968:	02f49623          	sh	a5,44(s1)
    ip->nlink = dip->nlink;
8000496c:	00659783          	lh	a5,6(a1)
80004970:	02f49723          	sh	a5,46(s1)
    ip->size = dip->size;
80004974:	0085a783          	lw	a5,8(a1)
80004978:	02f4a823          	sw	a5,48(s1)
    memmove(ip->addrs, dip->addrs, sizeof(ip->addrs));
8000497c:	03400613          	li	a2,52
80004980:	00c58593          	addi	a1,a1,12
80004984:	00c48533          	add	a0,s1,a2
80004988:	ffffc097          	auipc	ra,0xffffc
8000498c:	6d4080e7          	jalr	1748(ra) # 8000105c <memmove>
    brelse(bp);
80004990:	00090513          	mv	a0,s2
80004994:	fffff097          	auipc	ra,0xfffff
80004998:	63c080e7          	jalr	1596(ra) # 80003fd0 <brelse>
    ip->valid = 1;
8000499c:	00100793          	li	a5,1
800049a0:	02f4a223          	sw	a5,36(s1)
    if(ip->type == 0)
800049a4:	02849783          	lh	a5,40(s1)
800049a8:	00078663          	beqz	a5,800049b4 <ilock+0xfc>
800049ac:	00012903          	lw	s2,0(sp)
800049b0:	f41ff06f          	j	800048f0 <ilock+0x38>
      panic("ilock: no type");
800049b4:	00005517          	auipc	a0,0x5
800049b8:	ba050513          	addi	a0,a0,-1120 # 80009554 <userret+0x4b4>
800049bc:	ffffc097          	auipc	ra,0xffffc
800049c0:	d40080e7          	jalr	-704(ra) # 800006fc <panic>

800049c4 <iunlock>:
{
800049c4:	ff010113          	addi	sp,sp,-16
800049c8:	00112623          	sw	ra,12(sp)
800049cc:	00812423          	sw	s0,8(sp)
800049d0:	00912223          	sw	s1,4(sp)
800049d4:	01212023          	sw	s2,0(sp)
800049d8:	01010413          	addi	s0,sp,16
  if(ip == 0 || !holdingsleep(&ip->lock) || ip->ref < 1)
800049dc:	04050463          	beqz	a0,80004a24 <iunlock+0x60>
800049e0:	00050493          	mv	s1,a0
800049e4:	00c50913          	addi	s2,a0,12
800049e8:	00090513          	mv	a0,s2
800049ec:	00001097          	auipc	ra,0x1
800049f0:	16c080e7          	jalr	364(ra) # 80005b58 <holdingsleep>
800049f4:	02050863          	beqz	a0,80004a24 <iunlock+0x60>
800049f8:	0084a783          	lw	a5,8(s1)
800049fc:	02f05463          	blez	a5,80004a24 <iunlock+0x60>
  releasesleep(&ip->lock);
80004a00:	00090513          	mv	a0,s2
80004a04:	00001097          	auipc	ra,0x1
80004a08:	0f0080e7          	jalr	240(ra) # 80005af4 <releasesleep>
}
80004a0c:	00c12083          	lw	ra,12(sp)
80004a10:	00812403          	lw	s0,8(sp)
80004a14:	00412483          	lw	s1,4(sp)
80004a18:	00012903          	lw	s2,0(sp)
80004a1c:	01010113          	addi	sp,sp,16
80004a20:	00008067          	ret
    panic("iunlock");
80004a24:	00005517          	auipc	a0,0x5
80004a28:	b4050513          	addi	a0,a0,-1216 # 80009564 <userret+0x4c4>
80004a2c:	ffffc097          	auipc	ra,0xffffc
80004a30:	cd0080e7          	jalr	-816(ra) # 800006fc <panic>

80004a34 <iput>:
{
80004a34:	fe010113          	addi	sp,sp,-32
80004a38:	00112e23          	sw	ra,28(sp)
80004a3c:	00812c23          	sw	s0,24(sp)
80004a40:	00912a23          	sw	s1,20(sp)
80004a44:	02010413          	addi	s0,sp,32
80004a48:	00050493          	mv	s1,a0
  acquire(&icache.lock);
80004a4c:	0001a517          	auipc	a0,0x1a
80004a50:	f9850513          	addi	a0,a0,-104 # 8001e9e4 <icache>
80004a54:	ffffc097          	auipc	ra,0xffffc
80004a58:	4a8080e7          	jalr	1192(ra) # 80000efc <acquire>
  if(ip->ref == 1 && ip->valid && ip->nlink == 0){
80004a5c:	0084a703          	lw	a4,8(s1)
80004a60:	00100793          	li	a5,1
80004a64:	02f70a63          	beq	a4,a5,80004a98 <iput+0x64>
  ip->ref--;
80004a68:	0084a783          	lw	a5,8(s1)
80004a6c:	fff78793          	addi	a5,a5,-1
80004a70:	00f4a423          	sw	a5,8(s1)
  release(&icache.lock);
80004a74:	0001a517          	auipc	a0,0x1a
80004a78:	f7050513          	addi	a0,a0,-144 # 8001e9e4 <icache>
80004a7c:	ffffc097          	auipc	ra,0xffffc
80004a80:	4f4080e7          	jalr	1268(ra) # 80000f70 <release>
}
80004a84:	01c12083          	lw	ra,28(sp)
80004a88:	01812403          	lw	s0,24(sp)
80004a8c:	01412483          	lw	s1,20(sp)
80004a90:	02010113          	addi	sp,sp,32
80004a94:	00008067          	ret
  if(ip->ref == 1 && ip->valid && ip->nlink == 0){
80004a98:	0244a783          	lw	a5,36(s1)
80004a9c:	fc0786e3          	beqz	a5,80004a68 <iput+0x34>
80004aa0:	02e49783          	lh	a5,46(s1)
80004aa4:	fc0792e3          	bnez	a5,80004a68 <iput+0x34>
80004aa8:	01212823          	sw	s2,16(sp)
80004aac:	01312623          	sw	s3,12(sp)
80004ab0:	01412423          	sw	s4,8(sp)
    acquiresleep(&ip->lock);
80004ab4:	00c48793          	addi	a5,s1,12
80004ab8:	00078a13          	mv	s4,a5
80004abc:	00078513          	mv	a0,a5
80004ac0:	00001097          	auipc	ra,0x1
80004ac4:	fac080e7          	jalr	-84(ra) # 80005a6c <acquiresleep>
    release(&icache.lock);
80004ac8:	0001a517          	auipc	a0,0x1a
80004acc:	f1c50513          	addi	a0,a0,-228 # 8001e9e4 <icache>
80004ad0:	ffffc097          	auipc	ra,0xffffc
80004ad4:	4a0080e7          	jalr	1184(ra) # 80000f70 <release>
{
  int i, j;
  struct buf *bp;
  uint *a;

  for(i = 0; i < NDIRECT; i++){
80004ad8:	03448913          	addi	s2,s1,52
80004adc:	06448993          	addi	s3,s1,100
80004ae0:	00c0006f          	j	80004aec <iput+0xb8>
80004ae4:	00490913          	addi	s2,s2,4
80004ae8:	03390063          	beq	s2,s3,80004b08 <iput+0xd4>
    if(ip->addrs[i]){
80004aec:	00092583          	lw	a1,0(s2)
80004af0:	fe058ae3          	beqz	a1,80004ae4 <iput+0xb0>
      bfree(ip->dev, ip->addrs[i]);
80004af4:	0004a503          	lw	a0,0(s1)
80004af8:	fffff097          	auipc	ra,0xfffff
80004afc:	658080e7          	jalr	1624(ra) # 80004150 <bfree>
      ip->addrs[i] = 0;
80004b00:	00092023          	sw	zero,0(s2)
80004b04:	fe1ff06f          	j	80004ae4 <iput+0xb0>
    }
  }

  if(ip->addrs[NDIRECT]){
80004b08:	0644a583          	lw	a1,100(s1)
80004b0c:	04059a63          	bnez	a1,80004b60 <iput+0x12c>
    brelse(bp);
    bfree(ip->dev, ip->addrs[NDIRECT]);
    ip->addrs[NDIRECT] = 0;
  }

  ip->size = 0;
80004b10:	0204a823          	sw	zero,48(s1)
  iupdate(ip);
80004b14:	00048513          	mv	a0,s1
80004b18:	00000097          	auipc	ra,0x0
80004b1c:	c84080e7          	jalr	-892(ra) # 8000479c <iupdate>
    ip->type = 0;
80004b20:	02049423          	sh	zero,40(s1)
    iupdate(ip);
80004b24:	00048513          	mv	a0,s1
80004b28:	00000097          	auipc	ra,0x0
80004b2c:	c74080e7          	jalr	-908(ra) # 8000479c <iupdate>
    ip->valid = 0;
80004b30:	0204a223          	sw	zero,36(s1)
    releasesleep(&ip->lock);
80004b34:	000a0513          	mv	a0,s4
80004b38:	00001097          	auipc	ra,0x1
80004b3c:	fbc080e7          	jalr	-68(ra) # 80005af4 <releasesleep>
    acquire(&icache.lock);
80004b40:	0001a517          	auipc	a0,0x1a
80004b44:	ea450513          	addi	a0,a0,-348 # 8001e9e4 <icache>
80004b48:	ffffc097          	auipc	ra,0xffffc
80004b4c:	3b4080e7          	jalr	948(ra) # 80000efc <acquire>
80004b50:	01012903          	lw	s2,16(sp)
80004b54:	00c12983          	lw	s3,12(sp)
80004b58:	00812a03          	lw	s4,8(sp)
80004b5c:	f0dff06f          	j	80004a68 <iput+0x34>
80004b60:	01512223          	sw	s5,4(sp)
    bp = bread(ip->dev, ip->addrs[NDIRECT]);
80004b64:	0004a503          	lw	a0,0(s1)
80004b68:	fffff097          	auipc	ra,0xfffff
80004b6c:	2cc080e7          	jalr	716(ra) # 80003e34 <bread>
80004b70:	00050a93          	mv	s5,a0
    for(j = 0; j < NINDIRECT; j++){
80004b74:	03850913          	addi	s2,a0,56
80004b78:	43850993          	addi	s3,a0,1080
80004b7c:	0180006f          	j	80004b94 <iput+0x160>
        bfree(ip->dev, a[j]);
80004b80:	0004a503          	lw	a0,0(s1)
80004b84:	fffff097          	auipc	ra,0xfffff
80004b88:	5cc080e7          	jalr	1484(ra) # 80004150 <bfree>
    for(j = 0; j < NINDIRECT; j++){
80004b8c:	00490913          	addi	s2,s2,4
80004b90:	01390863          	beq	s2,s3,80004ba0 <iput+0x16c>
      if(a[j])
80004b94:	00092583          	lw	a1,0(s2)
80004b98:	fe058ae3          	beqz	a1,80004b8c <iput+0x158>
80004b9c:	fe5ff06f          	j	80004b80 <iput+0x14c>
    brelse(bp);
80004ba0:	000a8513          	mv	a0,s5
80004ba4:	fffff097          	auipc	ra,0xfffff
80004ba8:	42c080e7          	jalr	1068(ra) # 80003fd0 <brelse>
    bfree(ip->dev, ip->addrs[NDIRECT]);
80004bac:	0644a583          	lw	a1,100(s1)
80004bb0:	0004a503          	lw	a0,0(s1)
80004bb4:	fffff097          	auipc	ra,0xfffff
80004bb8:	59c080e7          	jalr	1436(ra) # 80004150 <bfree>
    ip->addrs[NDIRECT] = 0;
80004bbc:	0604a223          	sw	zero,100(s1)
80004bc0:	00412a83          	lw	s5,4(sp)
80004bc4:	f4dff06f          	j	80004b10 <iput+0xdc>

80004bc8 <iunlockput>:
{
80004bc8:	ff010113          	addi	sp,sp,-16
80004bcc:	00112623          	sw	ra,12(sp)
80004bd0:	00812423          	sw	s0,8(sp)
80004bd4:	00912223          	sw	s1,4(sp)
80004bd8:	01010413          	addi	s0,sp,16
80004bdc:	00050493          	mv	s1,a0
  iunlock(ip);
80004be0:	00000097          	auipc	ra,0x0
80004be4:	de4080e7          	jalr	-540(ra) # 800049c4 <iunlock>
  iput(ip);
80004be8:	00048513          	mv	a0,s1
80004bec:	00000097          	auipc	ra,0x0
80004bf0:	e48080e7          	jalr	-440(ra) # 80004a34 <iput>
}
80004bf4:	00c12083          	lw	ra,12(sp)
80004bf8:	00812403          	lw	s0,8(sp)
80004bfc:	00412483          	lw	s1,4(sp)
80004c00:	01010113          	addi	sp,sp,16
80004c04:	00008067          	ret

80004c08 <stati>:

// Copy stat information from inode.
// Caller must hold ip->lock.
void
stati(struct inode *ip, struct stat *st)
{
80004c08:	ff010113          	addi	sp,sp,-16
80004c0c:	00112623          	sw	ra,12(sp)
80004c10:	00812423          	sw	s0,8(sp)
80004c14:	01010413          	addi	s0,sp,16
  st->dev = ip->dev;
80004c18:	00052783          	lw	a5,0(a0)
80004c1c:	00f5a023          	sw	a5,0(a1)
  st->ino = ip->inum;
80004c20:	00452783          	lw	a5,4(a0)
80004c24:	00f5a223          	sw	a5,4(a1)
  st->type = ip->type;
80004c28:	02851783          	lh	a5,40(a0)
80004c2c:	00f59423          	sh	a5,8(a1)
  st->nlink = ip->nlink;
80004c30:	02e51783          	lh	a5,46(a0)
80004c34:	00f59523          	sh	a5,10(a1)
  st->size = ip->size;
80004c38:	03052783          	lw	a5,48(a0)
80004c3c:	00f5a823          	sw	a5,16(a1)
80004c40:	0005aa23          	sw	zero,20(a1)
}
80004c44:	00c12083          	lw	ra,12(sp)
80004c48:	00812403          	lw	s0,8(sp)
80004c4c:	01010113          	addi	sp,sp,16
80004c50:	00008067          	ret

80004c54 <readi>:
readi(struct inode *ip, int user_dst, uint32 dst, uint off, uint n)
{
  uint tot, m;
  struct buf *bp;

  if(off > ip->size || off + n < off)
80004c54:	03052783          	lw	a5,48(a0)
80004c58:	14d7e863          	bltu	a5,a3,80004da8 <readi+0x154>
{
80004c5c:	fd010113          	addi	sp,sp,-48
80004c60:	02112623          	sw	ra,44(sp)
80004c64:	02812423          	sw	s0,40(sp)
80004c68:	01312e23          	sw	s3,28(sp)
80004c6c:	01512a23          	sw	s5,20(sp)
80004c70:	01612823          	sw	s6,16(sp)
80004c74:	01712623          	sw	s7,12(sp)
80004c78:	01812423          	sw	s8,8(sp)
80004c7c:	03010413          	addi	s0,sp,48
80004c80:	00050b93          	mv	s7,a0
80004c84:	00058c13          	mv	s8,a1
80004c88:	00060a93          	mv	s5,a2
80004c8c:	00068993          	mv	s3,a3
80004c90:	00070b13          	mv	s6,a4
  if(off > ip->size || off + n < off)
80004c94:	00e68733          	add	a4,a3,a4
80004c98:	10d76c63          	bltu	a4,a3,80004db0 <readi+0x15c>
    return -1;
  if(off + n > ip->size)
80004c9c:	00e7f463          	bgeu	a5,a4,80004ca4 <readi+0x50>
    n = ip->size - off;
80004ca0:	40d78b33          	sub	s6,a5,a3

  for(tot=0; tot<n; tot+=m, off+=m, dst+=m){
80004ca4:	0c0b0263          	beqz	s6,80004d68 <readi+0x114>
80004ca8:	02912223          	sw	s1,36(sp)
80004cac:	03212023          	sw	s2,32(sp)
80004cb0:	01412c23          	sw	s4,24(sp)
80004cb4:	01912223          	sw	s9,4(sp)
80004cb8:	01a12023          	sw	s10,0(sp)
80004cbc:	00000a13          	li	s4,0
    bp = bread(ip->dev, bmap(ip, off/BSIZE));
    m = min(n - tot, BSIZE - off%BSIZE);
80004cc0:	40000d13          	li	s10,1024
    if(either_copyout(user_dst, dst, bp->data + (off % BSIZE), m) == -1) {
80004cc4:	fff00c93          	li	s9,-1
80004cc8:	0400006f          	j	80004d08 <readi+0xb4>
80004ccc:	03890613          	addi	a2,s2,56
80004cd0:	00048693          	mv	a3,s1
80004cd4:	00f60633          	add	a2,a2,a5
80004cd8:	000a8593          	mv	a1,s5
80004cdc:	000c0513          	mv	a0,s8
80004ce0:	ffffe097          	auipc	ra,0xffffe
80004ce4:	394080e7          	jalr	916(ra) # 80003074 <either_copyout>
80004ce8:	07950063          	beq	a0,s9,80004d48 <readi+0xf4>
      brelse(bp);
      break;
    }
    brelse(bp);
80004cec:	00090513          	mv	a0,s2
80004cf0:	fffff097          	auipc	ra,0xfffff
80004cf4:	2e0080e7          	jalr	736(ra) # 80003fd0 <brelse>
  for(tot=0; tot<n; tot+=m, off+=m, dst+=m){
80004cf8:	009a0a33          	add	s4,s4,s1
80004cfc:	009989b3          	add	s3,s3,s1
80004d00:	009a8ab3          	add	s5,s5,s1
80004d04:	096a7663          	bgeu	s4,s6,80004d90 <readi+0x13c>
    bp = bread(ip->dev, bmap(ip, off/BSIZE));
80004d08:	000ba483          	lw	s1,0(s7)
80004d0c:	00a9d593          	srli	a1,s3,0xa
80004d10:	000b8513          	mv	a0,s7
80004d14:	fffff097          	auipc	ra,0xfffff
80004d18:	658080e7          	jalr	1624(ra) # 8000436c <bmap>
80004d1c:	00050593          	mv	a1,a0
80004d20:	00048513          	mv	a0,s1
80004d24:	fffff097          	auipc	ra,0xfffff
80004d28:	110080e7          	jalr	272(ra) # 80003e34 <bread>
80004d2c:	00050913          	mv	s2,a0
    m = min(n - tot, BSIZE - off%BSIZE);
80004d30:	3ff9f793          	andi	a5,s3,1023
80004d34:	414b0733          	sub	a4,s6,s4
80004d38:	40fd04b3          	sub	s1,s10,a5
80004d3c:	f89778e3          	bgeu	a4,s1,80004ccc <readi+0x78>
80004d40:	00070493          	mv	s1,a4
80004d44:	f89ff06f          	j	80004ccc <readi+0x78>
      brelse(bp);
80004d48:	00090513          	mv	a0,s2
80004d4c:	fffff097          	auipc	ra,0xfffff
80004d50:	284080e7          	jalr	644(ra) # 80003fd0 <brelse>
      break;
80004d54:	02412483          	lw	s1,36(sp)
80004d58:	02012903          	lw	s2,32(sp)
80004d5c:	01812a03          	lw	s4,24(sp)
80004d60:	00412c83          	lw	s9,4(sp)
80004d64:	00012d03          	lw	s10,0(sp)
  }
  return n;
80004d68:	000b0513          	mv	a0,s6
}
80004d6c:	02c12083          	lw	ra,44(sp)
80004d70:	02812403          	lw	s0,40(sp)
80004d74:	01c12983          	lw	s3,28(sp)
80004d78:	01412a83          	lw	s5,20(sp)
80004d7c:	01012b03          	lw	s6,16(sp)
80004d80:	00c12b83          	lw	s7,12(sp)
80004d84:	00812c03          	lw	s8,8(sp)
80004d88:	03010113          	addi	sp,sp,48
80004d8c:	00008067          	ret
80004d90:	02412483          	lw	s1,36(sp)
80004d94:	02012903          	lw	s2,32(sp)
80004d98:	01812a03          	lw	s4,24(sp)
80004d9c:	00412c83          	lw	s9,4(sp)
80004da0:	00012d03          	lw	s10,0(sp)
80004da4:	fc5ff06f          	j	80004d68 <readi+0x114>
    return -1;
80004da8:	fff00513          	li	a0,-1
}
80004dac:	00008067          	ret
    return -1;
80004db0:	fff00513          	li	a0,-1
80004db4:	fb9ff06f          	j	80004d6c <readi+0x118>

80004db8 <writei>:
writei(struct inode *ip, int user_src, uint32 src, uint off, uint n)
{
  uint tot, m;
  struct buf *bp;

  if(off > ip->size || off + n < off)
80004db8:	03052783          	lw	a5,48(a0)
80004dbc:	14d7ee63          	bltu	a5,a3,80004f18 <writei+0x160>
{
80004dc0:	fd010113          	addi	sp,sp,-48
80004dc4:	02112623          	sw	ra,44(sp)
80004dc8:	02812423          	sw	s0,40(sp)
80004dcc:	01312e23          	sw	s3,28(sp)
80004dd0:	01512a23          	sw	s5,20(sp)
80004dd4:	01612823          	sw	s6,16(sp)
80004dd8:	01712623          	sw	s7,12(sp)
80004ddc:	01812423          	sw	s8,8(sp)
80004de0:	03010413          	addi	s0,sp,48
80004de4:	00050b93          	mv	s7,a0
80004de8:	00058c13          	mv	s8,a1
80004dec:	00060a93          	mv	s5,a2
80004df0:	00068993          	mv	s3,a3
80004df4:	00070b13          	mv	s6,a4
  if(off > ip->size || off + n < off)
80004df8:	00e687b3          	add	a5,a3,a4
    return -1;
  if(off + n > MAXFILE*BSIZE)
80004dfc:	00043737          	lui	a4,0x43
80004e00:	12f76063          	bltu	a4,a5,80004f20 <writei+0x168>
80004e04:	10d7ee63          	bltu	a5,a3,80004f20 <writei+0x168>
    return -1;

  for(tot=0; tot<n; tot+=m, off+=m, src+=m){
80004e08:	0e0b0463          	beqz	s6,80004ef0 <writei+0x138>
80004e0c:	02912223          	sw	s1,36(sp)
80004e10:	03212023          	sw	s2,32(sp)
80004e14:	01412c23          	sw	s4,24(sp)
80004e18:	01912223          	sw	s9,4(sp)
80004e1c:	01a12023          	sw	s10,0(sp)
80004e20:	00000a13          	li	s4,0
    bp = bread(ip->dev, bmap(ip, off/BSIZE));
    m = min(n - tot, BSIZE - off%BSIZE);
80004e24:	40000d13          	li	s10,1024
    if(either_copyin(bp->data + (off % BSIZE), user_src, src, m) == -1) {
80004e28:	fff00c93          	li	s9,-1
80004e2c:	04c0006f          	j	80004e78 <writei+0xc0>
80004e30:	03890793          	addi	a5,s2,56
80004e34:	00048693          	mv	a3,s1
80004e38:	000a8613          	mv	a2,s5
80004e3c:	000c0593          	mv	a1,s8
80004e40:	00a78533          	add	a0,a5,a0
80004e44:	ffffe097          	auipc	ra,0xffffe
80004e48:	2c0080e7          	jalr	704(ra) # 80003104 <either_copyin>
80004e4c:	07950663          	beq	a0,s9,80004eb8 <writei+0x100>
      brelse(bp);
      break;
    }
    log_write(bp);
80004e50:	00090513          	mv	a0,s2
80004e54:	00001097          	auipc	ra,0x1
80004e58:	a94080e7          	jalr	-1388(ra) # 800058e8 <log_write>
    brelse(bp);
80004e5c:	00090513          	mv	a0,s2
80004e60:	fffff097          	auipc	ra,0xfffff
80004e64:	170080e7          	jalr	368(ra) # 80003fd0 <brelse>
  for(tot=0; tot<n; tot+=m, off+=m, src+=m){
80004e68:	009a0a33          	add	s4,s4,s1
80004e6c:	009989b3          	add	s3,s3,s1
80004e70:	009a8ab3          	add	s5,s5,s1
80004e74:	056a7863          	bgeu	s4,s6,80004ec4 <writei+0x10c>
    bp = bread(ip->dev, bmap(ip, off/BSIZE));
80004e78:	000ba483          	lw	s1,0(s7)
80004e7c:	00a9d593          	srli	a1,s3,0xa
80004e80:	000b8513          	mv	a0,s7
80004e84:	fffff097          	auipc	ra,0xfffff
80004e88:	4e8080e7          	jalr	1256(ra) # 8000436c <bmap>
80004e8c:	00050593          	mv	a1,a0
80004e90:	00048513          	mv	a0,s1
80004e94:	fffff097          	auipc	ra,0xfffff
80004e98:	fa0080e7          	jalr	-96(ra) # 80003e34 <bread>
80004e9c:	00050913          	mv	s2,a0
    m = min(n - tot, BSIZE - off%BSIZE);
80004ea0:	3ff9f513          	andi	a0,s3,1023
80004ea4:	414b07b3          	sub	a5,s6,s4
80004ea8:	40ad04b3          	sub	s1,s10,a0
80004eac:	f897f2e3          	bgeu	a5,s1,80004e30 <writei+0x78>
80004eb0:	00078493          	mv	s1,a5
80004eb4:	f7dff06f          	j	80004e30 <writei+0x78>
      brelse(bp);
80004eb8:	00090513          	mv	a0,s2
80004ebc:	fffff097          	auipc	ra,0xfffff
80004ec0:	114080e7          	jalr	276(ra) # 80003fd0 <brelse>
  }

  if(n > 0){
    if(off > ip->size)
80004ec4:	030ba783          	lw	a5,48(s7)
80004ec8:	0137f463          	bgeu	a5,s3,80004ed0 <writei+0x118>
      ip->size = off;
80004ecc:	033ba823          	sw	s3,48(s7)
    // write the i-node back to disk even if the size didn't change
    // because the loop above might have called bmap() and added a new
    // block to ip->addrs[].
    iupdate(ip);
80004ed0:	000b8513          	mv	a0,s7
80004ed4:	00000097          	auipc	ra,0x0
80004ed8:	8c8080e7          	jalr	-1848(ra) # 8000479c <iupdate>
80004edc:	02412483          	lw	s1,36(sp)
80004ee0:	02012903          	lw	s2,32(sp)
80004ee4:	01812a03          	lw	s4,24(sp)
80004ee8:	00412c83          	lw	s9,4(sp)
80004eec:	00012d03          	lw	s10,0(sp)
  }

  return n;
80004ef0:	000b0513          	mv	a0,s6
}
80004ef4:	02c12083          	lw	ra,44(sp)
80004ef8:	02812403          	lw	s0,40(sp)
80004efc:	01c12983          	lw	s3,28(sp)
80004f00:	01412a83          	lw	s5,20(sp)
80004f04:	01012b03          	lw	s6,16(sp)
80004f08:	00c12b83          	lw	s7,12(sp)
80004f0c:	00812c03          	lw	s8,8(sp)
80004f10:	03010113          	addi	sp,sp,48
80004f14:	00008067          	ret
    return -1;
80004f18:	fff00513          	li	a0,-1
}
80004f1c:	00008067          	ret
    return -1;
80004f20:	fff00513          	li	a0,-1
80004f24:	fd1ff06f          	j	80004ef4 <writei+0x13c>

80004f28 <namecmp>:

// Directories

int
namecmp(const char *s, const char *t)
{
80004f28:	ff010113          	addi	sp,sp,-16
80004f2c:	00112623          	sw	ra,12(sp)
80004f30:	00812423          	sw	s0,8(sp)
80004f34:	01010413          	addi	s0,sp,16
  return strncmp(s, t, DIRSIZ);
80004f38:	00e00613          	li	a2,14
80004f3c:	ffffc097          	auipc	ra,0xffffc
80004f40:	1b4080e7          	jalr	436(ra) # 800010f0 <strncmp>
}
80004f44:	00c12083          	lw	ra,12(sp)
80004f48:	00812403          	lw	s0,8(sp)
80004f4c:	01010113          	addi	sp,sp,16
80004f50:	00008067          	ret

80004f54 <dirlookup>:

// Look for a directory entry in a directory.
// If found, set *poff to byte offset of entry.
struct inode*
dirlookup(struct inode *dp, char *name, uint *poff)
{
80004f54:	fc010113          	addi	sp,sp,-64
80004f58:	02112e23          	sw	ra,60(sp)
80004f5c:	02812c23          	sw	s0,56(sp)
80004f60:	02912a23          	sw	s1,52(sp)
80004f64:	03212823          	sw	s2,48(sp)
80004f68:	03312623          	sw	s3,44(sp)
80004f6c:	03412423          	sw	s4,40(sp)
80004f70:	03512223          	sw	s5,36(sp)
80004f74:	03612023          	sw	s6,32(sp)
80004f78:	01712e23          	sw	s7,28(sp)
80004f7c:	04010413          	addi	s0,sp,64
  uint off, inum;
  struct dirent de;

  if(dp->type != T_DIR)
80004f80:	02851703          	lh	a4,40(a0)
80004f84:	00100793          	li	a5,1
80004f88:	02f71863          	bne	a4,a5,80004fb8 <dirlookup+0x64>
80004f8c:	00050913          	mv	s2,a0
80004f90:	00058a93          	mv	s5,a1
80004f94:	00060b93          	mv	s7,a2
    panic("dirlookup not DIR");

  for(off = 0; off < dp->size; off += sizeof(de)){
80004f98:	03052783          	lw	a5,48(a0)
80004f9c:	00000493          	li	s1,0
    if(readi(dp, 0, (uint32)&de, off, sizeof(de)) != sizeof(de))
80004fa0:	fc040a13          	addi	s4,s0,-64
80004fa4:	01000993          	li	s3,16
      panic("dirlookup read");
    if(de.inum == 0)
      continue;
    if(namecmp(name, de.name) == 0){
80004fa8:	fc240b13          	addi	s6,s0,-62
      inum = de.inum;
      return iget(dp->dev, inum);
    }
  }

  return 0;
80004fac:	00000513          	li	a0,0
  for(off = 0; off < dp->size; off += sizeof(de)){
80004fb0:	02079a63          	bnez	a5,80004fe4 <dirlookup+0x90>
80004fb4:	08c0006f          	j	80005040 <dirlookup+0xec>
    panic("dirlookup not DIR");
80004fb8:	00004517          	auipc	a0,0x4
80004fbc:	5b450513          	addi	a0,a0,1460 # 8000956c <userret+0x4cc>
80004fc0:	ffffb097          	auipc	ra,0xffffb
80004fc4:	73c080e7          	jalr	1852(ra) # 800006fc <panic>
      panic("dirlookup read");
80004fc8:	00004517          	auipc	a0,0x4
80004fcc:	5b850513          	addi	a0,a0,1464 # 80009580 <userret+0x4e0>
80004fd0:	ffffb097          	auipc	ra,0xffffb
80004fd4:	72c080e7          	jalr	1836(ra) # 800006fc <panic>
  for(off = 0; off < dp->size; off += sizeof(de)){
80004fd8:	01048493          	addi	s1,s1,16
80004fdc:	03092783          	lw	a5,48(s2)
80004fe0:	04f4fe63          	bgeu	s1,a5,8000503c <dirlookup+0xe8>
    if(readi(dp, 0, (uint32)&de, off, sizeof(de)) != sizeof(de))
80004fe4:	00098713          	mv	a4,s3
80004fe8:	00048693          	mv	a3,s1
80004fec:	000a0613          	mv	a2,s4
80004ff0:	00000593          	li	a1,0
80004ff4:	00090513          	mv	a0,s2
80004ff8:	00000097          	auipc	ra,0x0
80004ffc:	c5c080e7          	jalr	-932(ra) # 80004c54 <readi>
80005000:	fd3514e3          	bne	a0,s3,80004fc8 <dirlookup+0x74>
    if(de.inum == 0)
80005004:	fc045783          	lhu	a5,-64(s0)
80005008:	fc0788e3          	beqz	a5,80004fd8 <dirlookup+0x84>
    if(namecmp(name, de.name) == 0){
8000500c:	000b0593          	mv	a1,s6
80005010:	000a8513          	mv	a0,s5
80005014:	00000097          	auipc	ra,0x0
80005018:	f14080e7          	jalr	-236(ra) # 80004f28 <namecmp>
8000501c:	fa051ee3          	bnez	a0,80004fd8 <dirlookup+0x84>
      if(poff)
80005020:	000b8463          	beqz	s7,80005028 <dirlookup+0xd4>
        *poff = off;
80005024:	009ba023          	sw	s1,0(s7)
      return iget(dp->dev, inum);
80005028:	fc045583          	lhu	a1,-64(s0)
8000502c:	00092503          	lw	a0,0(s2)
80005030:	fffff097          	auipc	ra,0xfffff
80005034:	444080e7          	jalr	1092(ra) # 80004474 <iget>
80005038:	0080006f          	j	80005040 <dirlookup+0xec>
  return 0;
8000503c:	00000513          	li	a0,0
}
80005040:	03c12083          	lw	ra,60(sp)
80005044:	03812403          	lw	s0,56(sp)
80005048:	03412483          	lw	s1,52(sp)
8000504c:	03012903          	lw	s2,48(sp)
80005050:	02c12983          	lw	s3,44(sp)
80005054:	02812a03          	lw	s4,40(sp)
80005058:	02412a83          	lw	s5,36(sp)
8000505c:	02012b03          	lw	s6,32(sp)
80005060:	01c12b83          	lw	s7,28(sp)
80005064:	04010113          	addi	sp,sp,64
80005068:	00008067          	ret

8000506c <namex>:
// If parent != 0, return the inode for the parent and copy the final
// path element into name, which must have room for DIRSIZ bytes.
// Must be called inside a transaction since it calls iput().
static struct inode*
namex(char *path, int nameiparent, char *name)
{
8000506c:	fd010113          	addi	sp,sp,-48
80005070:	02112623          	sw	ra,44(sp)
80005074:	02812423          	sw	s0,40(sp)
80005078:	02912223          	sw	s1,36(sp)
8000507c:	03212023          	sw	s2,32(sp)
80005080:	01312e23          	sw	s3,28(sp)
80005084:	01412c23          	sw	s4,24(sp)
80005088:	01512a23          	sw	s5,20(sp)
8000508c:	01612823          	sw	s6,16(sp)
80005090:	01712623          	sw	s7,12(sp)
80005094:	01812423          	sw	s8,8(sp)
80005098:	01912223          	sw	s9,4(sp)
8000509c:	01a12023          	sw	s10,0(sp)
800050a0:	03010413          	addi	s0,sp,48
800050a4:	00050493          	mv	s1,a0
800050a8:	00058b13          	mv	s6,a1
800050ac:	00060a93          	mv	s5,a2
  struct inode *ip, *next;

  if(*path == '/')
800050b0:	00054703          	lbu	a4,0(a0)
800050b4:	02f00793          	li	a5,47
800050b8:	02f70863          	beq	a4,a5,800050e8 <namex+0x7c>
    ip = iget(ROOTDEV, ROOTINO);
  else
    ip = idup(myproc()->cwd);
800050bc:	ffffd097          	auipc	ra,0xffffd
800050c0:	220080e7          	jalr	544(ra) # 800022dc <myproc>
800050c4:	0ac52503          	lw	a0,172(a0)
800050c8:	fffff097          	auipc	ra,0xfffff
800050cc:	794080e7          	jalr	1940(ra) # 8000485c <idup>
800050d0:	00050a13          	mv	s4,a0
  while(*path == '/')
800050d4:	02f00993          	li	s3,47
  if(len >= DIRSIZ)
800050d8:	00d00c13          	li	s8,13
    memmove(name, s, DIRSIZ);
800050dc:	00e00c93          	li	s9,14

  while((path = skipelem(path, name)) != 0){
    ilock(ip);
    if(ip->type != T_DIR){
800050e0:	00100b93          	li	s7,1
800050e4:	10c0006f          	j	800051f0 <namex+0x184>
    ip = iget(ROOTDEV, ROOTINO);
800050e8:	00100593          	li	a1,1
800050ec:	00058513          	mv	a0,a1
800050f0:	fffff097          	auipc	ra,0xfffff
800050f4:	384080e7          	jalr	900(ra) # 80004474 <iget>
800050f8:	00050a13          	mv	s4,a0
800050fc:	fd9ff06f          	j	800050d4 <namex+0x68>
      iunlockput(ip);
80005100:	000a0513          	mv	a0,s4
80005104:	00000097          	auipc	ra,0x0
80005108:	ac4080e7          	jalr	-1340(ra) # 80004bc8 <iunlockput>
      return 0;
8000510c:	00000a13          	li	s4,0
  if(nameiparent){
    iput(ip);
    return 0;
  }
  return ip;
}
80005110:	000a0513          	mv	a0,s4
80005114:	02c12083          	lw	ra,44(sp)
80005118:	02812403          	lw	s0,40(sp)
8000511c:	02412483          	lw	s1,36(sp)
80005120:	02012903          	lw	s2,32(sp)
80005124:	01c12983          	lw	s3,28(sp)
80005128:	01812a03          	lw	s4,24(sp)
8000512c:	01412a83          	lw	s5,20(sp)
80005130:	01012b03          	lw	s6,16(sp)
80005134:	00c12b83          	lw	s7,12(sp)
80005138:	00812c03          	lw	s8,8(sp)
8000513c:	00412c83          	lw	s9,4(sp)
80005140:	00012d03          	lw	s10,0(sp)
80005144:	03010113          	addi	sp,sp,48
80005148:	00008067          	ret
      iunlock(ip);
8000514c:	000a0513          	mv	a0,s4
80005150:	00000097          	auipc	ra,0x0
80005154:	874080e7          	jalr	-1932(ra) # 800049c4 <iunlock>
      return ip;
80005158:	fb9ff06f          	j	80005110 <namex+0xa4>
      iunlockput(ip);
8000515c:	000a0513          	mv	a0,s4
80005160:	00000097          	auipc	ra,0x0
80005164:	a68080e7          	jalr	-1432(ra) # 80004bc8 <iunlockput>
      return 0;
80005168:	00090a13          	mv	s4,s2
8000516c:	fa5ff06f          	j	80005110 <namex+0xa4>
  len = path - s;
80005170:	40990d33          	sub	s10,s2,s1
  if(len >= DIRSIZ)
80005174:	0dac5463          	bge	s8,s10,8000523c <namex+0x1d0>
    memmove(name, s, DIRSIZ);
80005178:	000c8613          	mv	a2,s9
8000517c:	00048593          	mv	a1,s1
80005180:	000a8513          	mv	a0,s5
80005184:	ffffc097          	auipc	ra,0xffffc
80005188:	ed8080e7          	jalr	-296(ra) # 8000105c <memmove>
8000518c:	00090493          	mv	s1,s2
  while(*path == '/')
80005190:	0004c783          	lbu	a5,0(s1)
80005194:	01379863          	bne	a5,s3,800051a4 <namex+0x138>
    path++;
80005198:	00148493          	addi	s1,s1,1
  while(*path == '/')
8000519c:	0004c783          	lbu	a5,0(s1)
800051a0:	ff378ce3          	beq	a5,s3,80005198 <namex+0x12c>
    ilock(ip);
800051a4:	000a0513          	mv	a0,s4
800051a8:	fffff097          	auipc	ra,0xfffff
800051ac:	710080e7          	jalr	1808(ra) # 800048b8 <ilock>
    if(ip->type != T_DIR){
800051b0:	028a1783          	lh	a5,40(s4)
800051b4:	f57796e3          	bne	a5,s7,80005100 <namex+0x94>
    if(nameiparent && *path == '\0'){
800051b8:	000b0663          	beqz	s6,800051c4 <namex+0x158>
800051bc:	0004c783          	lbu	a5,0(s1)
800051c0:	f80786e3          	beqz	a5,8000514c <namex+0xe0>
    if((next = dirlookup(ip, name, 0)) == 0){
800051c4:	00000613          	li	a2,0
800051c8:	000a8593          	mv	a1,s5
800051cc:	000a0513          	mv	a0,s4
800051d0:	00000097          	auipc	ra,0x0
800051d4:	d84080e7          	jalr	-636(ra) # 80004f54 <dirlookup>
800051d8:	00050913          	mv	s2,a0
800051dc:	f80500e3          	beqz	a0,8000515c <namex+0xf0>
    iunlockput(ip);
800051e0:	000a0513          	mv	a0,s4
800051e4:	00000097          	auipc	ra,0x0
800051e8:	9e4080e7          	jalr	-1564(ra) # 80004bc8 <iunlockput>
    ip = next;
800051ec:	00090a13          	mv	s4,s2
  while(*path == '/')
800051f0:	0004c783          	lbu	a5,0(s1)
800051f4:	01379863          	bne	a5,s3,80005204 <namex+0x198>
    path++;
800051f8:	00148493          	addi	s1,s1,1
  while(*path == '/')
800051fc:	0004c783          	lbu	a5,0(s1)
80005200:	ff378ce3          	beq	a5,s3,800051f8 <namex+0x18c>
  if(*path == 0)
80005204:	04078e63          	beqz	a5,80005260 <namex+0x1f4>
  while(*path != '/' && *path != 0)
80005208:	0004c783          	lbu	a5,0(s1)
8000520c:	fd178713          	addi	a4,a5,-47
80005210:	02070263          	beqz	a4,80005234 <namex+0x1c8>
80005214:	02078063          	beqz	a5,80005234 <namex+0x1c8>
80005218:	00048913          	mv	s2,s1
    path++;
8000521c:	00190913          	addi	s2,s2,1
  while(*path != '/' && *path != 0)
80005220:	00094783          	lbu	a5,0(s2)
80005224:	fd178713          	addi	a4,a5,-47
80005228:	f40704e3          	beqz	a4,80005170 <namex+0x104>
8000522c:	fe0798e3          	bnez	a5,8000521c <namex+0x1b0>
80005230:	f41ff06f          	j	80005170 <namex+0x104>
80005234:	00048913          	mv	s2,s1
  len = path - s;
80005238:	00000d13          	li	s10,0
    memmove(name, s, len);
8000523c:	000d0613          	mv	a2,s10
80005240:	00048593          	mv	a1,s1
80005244:	000a8513          	mv	a0,s5
80005248:	ffffc097          	auipc	ra,0xffffc
8000524c:	e14080e7          	jalr	-492(ra) # 8000105c <memmove>
    name[len] = 0;
80005250:	01aa8d33          	add	s10,s5,s10
80005254:	000d0023          	sb	zero,0(s10)
80005258:	00090493          	mv	s1,s2
8000525c:	f35ff06f          	j	80005190 <namex+0x124>
  if(nameiparent){
80005260:	ea0b08e3          	beqz	s6,80005110 <namex+0xa4>
    iput(ip);
80005264:	000a0513          	mv	a0,s4
80005268:	fffff097          	auipc	ra,0xfffff
8000526c:	7cc080e7          	jalr	1996(ra) # 80004a34 <iput>
    return 0;
80005270:	00000a13          	li	s4,0
80005274:	e9dff06f          	j	80005110 <namex+0xa4>

80005278 <dirlink>:
{
80005278:	fd010113          	addi	sp,sp,-48
8000527c:	02112623          	sw	ra,44(sp)
80005280:	02812423          	sw	s0,40(sp)
80005284:	03212023          	sw	s2,32(sp)
80005288:	01512a23          	sw	s5,20(sp)
8000528c:	01612823          	sw	s6,16(sp)
80005290:	03010413          	addi	s0,sp,48
80005294:	00050913          	mv	s2,a0
80005298:	00058a93          	mv	s5,a1
8000529c:	00060b13          	mv	s6,a2
  if((ip = dirlookup(dp, name, 0)) != 0){
800052a0:	00000613          	li	a2,0
800052a4:	00000097          	auipc	ra,0x0
800052a8:	cb0080e7          	jalr	-848(ra) # 80004f54 <dirlookup>
800052ac:	06051263          	bnez	a0,80005310 <dirlink+0x98>
800052b0:	02912223          	sw	s1,36(sp)
  for(off = 0; off < dp->size; off += sizeof(de)){
800052b4:	03092483          	lw	s1,48(s2)
800052b8:	08048063          	beqz	s1,80005338 <dirlink+0xc0>
800052bc:	01312e23          	sw	s3,28(sp)
800052c0:	01412c23          	sw	s4,24(sp)
800052c4:	00000493          	li	s1,0
    if(readi(dp, 0, (uint32)&de, off, sizeof(de)) != sizeof(de))
800052c8:	fd040a13          	addi	s4,s0,-48
800052cc:	01000993          	li	s3,16
800052d0:	00098713          	mv	a4,s3
800052d4:	00048693          	mv	a3,s1
800052d8:	000a0613          	mv	a2,s4
800052dc:	00000593          	li	a1,0
800052e0:	00090513          	mv	a0,s2
800052e4:	00000097          	auipc	ra,0x0
800052e8:	970080e7          	jalr	-1680(ra) # 80004c54 <readi>
800052ec:	03351a63          	bne	a0,s3,80005320 <dirlink+0xa8>
    if(de.inum == 0)
800052f0:	fd045783          	lhu	a5,-48(s0)
800052f4:	02078e63          	beqz	a5,80005330 <dirlink+0xb8>
  for(off = 0; off < dp->size; off += sizeof(de)){
800052f8:	01048493          	addi	s1,s1,16
800052fc:	03092783          	lw	a5,48(s2)
80005300:	fcf4e8e3          	bltu	s1,a5,800052d0 <dirlink+0x58>
80005304:	01c12983          	lw	s3,28(sp)
80005308:	01812a03          	lw	s4,24(sp)
8000530c:	02c0006f          	j	80005338 <dirlink+0xc0>
    iput(ip);
80005310:	fffff097          	auipc	ra,0xfffff
80005314:	724080e7          	jalr	1828(ra) # 80004a34 <iput>
    return -1;
80005318:	fff00513          	li	a0,-1
8000531c:	0640006f          	j	80005380 <dirlink+0x108>
      panic("dirlink read");
80005320:	00004517          	auipc	a0,0x4
80005324:	27050513          	addi	a0,a0,624 # 80009590 <userret+0x4f0>
80005328:	ffffb097          	auipc	ra,0xffffb
8000532c:	3d4080e7          	jalr	980(ra) # 800006fc <panic>
80005330:	01c12983          	lw	s3,28(sp)
80005334:	01812a03          	lw	s4,24(sp)
  strncpy(de.name, name, DIRSIZ);
80005338:	00e00613          	li	a2,14
8000533c:	000a8593          	mv	a1,s5
80005340:	fd240513          	addi	a0,s0,-46
80005344:	ffffc097          	auipc	ra,0xffffc
80005348:	e0c080e7          	jalr	-500(ra) # 80001150 <strncpy>
  de.inum = inum;
8000534c:	fd641823          	sh	s6,-48(s0)
  if(writei(dp, 0, (uint32)&de, off, sizeof(de)) != sizeof(de))
80005350:	01000713          	li	a4,16
80005354:	00048693          	mv	a3,s1
80005358:	fd040613          	addi	a2,s0,-48
8000535c:	00000593          	li	a1,0
80005360:	00090513          	mv	a0,s2
80005364:	00000097          	auipc	ra,0x0
80005368:	a54080e7          	jalr	-1452(ra) # 80004db8 <writei>
8000536c:	00050713          	mv	a4,a0
80005370:	01000793          	li	a5,16
  return 0;
80005374:	00000513          	li	a0,0
  if(writei(dp, 0, (uint32)&de, off, sizeof(de)) != sizeof(de))
80005378:	02f71263          	bne	a4,a5,8000539c <dirlink+0x124>
8000537c:	02412483          	lw	s1,36(sp)
}
80005380:	02c12083          	lw	ra,44(sp)
80005384:	02812403          	lw	s0,40(sp)
80005388:	02012903          	lw	s2,32(sp)
8000538c:	01412a83          	lw	s5,20(sp)
80005390:	01012b03          	lw	s6,16(sp)
80005394:	03010113          	addi	sp,sp,48
80005398:	00008067          	ret
8000539c:	01312e23          	sw	s3,28(sp)
800053a0:	01412c23          	sw	s4,24(sp)
    panic("dirlink");
800053a4:	00004517          	auipc	a0,0x4
800053a8:	35450513          	addi	a0,a0,852 # 800096f8 <userret+0x658>
800053ac:	ffffb097          	auipc	ra,0xffffb
800053b0:	350080e7          	jalr	848(ra) # 800006fc <panic>

800053b4 <namei>:

struct inode*
namei(char *path)
{
800053b4:	fe010113          	addi	sp,sp,-32
800053b8:	00112e23          	sw	ra,28(sp)
800053bc:	00812c23          	sw	s0,24(sp)
800053c0:	02010413          	addi	s0,sp,32
  char name[DIRSIZ];
  return namex(path, 0, name);
800053c4:	fe040613          	addi	a2,s0,-32
800053c8:	00000593          	li	a1,0
800053cc:	00000097          	auipc	ra,0x0
800053d0:	ca0080e7          	jalr	-864(ra) # 8000506c <namex>
}
800053d4:	01c12083          	lw	ra,28(sp)
800053d8:	01812403          	lw	s0,24(sp)
800053dc:	02010113          	addi	sp,sp,32
800053e0:	00008067          	ret

800053e4 <nameiparent>:

struct inode*
nameiparent(char *path, char *name)
{
800053e4:	ff010113          	addi	sp,sp,-16
800053e8:	00112623          	sw	ra,12(sp)
800053ec:	00812423          	sw	s0,8(sp)
800053f0:	01010413          	addi	s0,sp,16
800053f4:	00058613          	mv	a2,a1
  return namex(path, 1, name);
800053f8:	00100593          	li	a1,1
800053fc:	00000097          	auipc	ra,0x0
80005400:	c70080e7          	jalr	-912(ra) # 8000506c <namex>
}
80005404:	00c12083          	lw	ra,12(sp)
80005408:	00812403          	lw	s0,8(sp)
8000540c:	01010113          	addi	sp,sp,16
80005410:	00008067          	ret

80005414 <write_head>:
// Write in-memory log header to disk.
// This is the true point at which the
// current transaction commits.
static void
write_head(void)
{
80005414:	ff010113          	addi	sp,sp,-16
80005418:	00112623          	sw	ra,12(sp)
8000541c:	00812423          	sw	s0,8(sp)
80005420:	00912223          	sw	s1,4(sp)
80005424:	01212023          	sw	s2,0(sp)
80005428:	01010413          	addi	s0,sp,16
  struct buf *buf = bread(log.dev, log.start);
8000542c:	0001b917          	auipc	s2,0x1b
80005430:	a1490913          	addi	s2,s2,-1516 # 8001fe40 <log>
80005434:	00c92583          	lw	a1,12(s2)
80005438:	01c92503          	lw	a0,28(s2)
8000543c:	fffff097          	auipc	ra,0xfffff
80005440:	9f8080e7          	jalr	-1544(ra) # 80003e34 <bread>
80005444:	00050493          	mv	s1,a0
  struct logheader *hb = (struct logheader *) (buf->data);
  int i;
  hb->n = log.lh.n;
80005448:	02092603          	lw	a2,32(s2)
8000544c:	02c52c23          	sw	a2,56(a0)
  for (i = 0; i < log.lh.n; i++) {
80005450:	02c05663          	blez	a2,8000547c <write_head+0x68>
80005454:	0001b717          	auipc	a4,0x1b
80005458:	a1070713          	addi	a4,a4,-1520 # 8001fe64 <log+0x24>
8000545c:	00050793          	mv	a5,a0
80005460:	00261613          	slli	a2,a2,0x2
80005464:	00a60633          	add	a2,a2,a0
    hb->block[i] = log.lh.block[i];
80005468:	00072683          	lw	a3,0(a4)
8000546c:	02d7ae23          	sw	a3,60(a5)
  for (i = 0; i < log.lh.n; i++) {
80005470:	00470713          	addi	a4,a4,4
80005474:	00478793          	addi	a5,a5,4
80005478:	fec798e3          	bne	a5,a2,80005468 <write_head+0x54>
  }
  bwrite(buf);
8000547c:	00048513          	mv	a0,s1
80005480:	fffff097          	auipc	ra,0xfffff
80005484:	af4080e7          	jalr	-1292(ra) # 80003f74 <bwrite>
  brelse(buf);
80005488:	00048513          	mv	a0,s1
8000548c:	fffff097          	auipc	ra,0xfffff
80005490:	b44080e7          	jalr	-1212(ra) # 80003fd0 <brelse>
}
80005494:	00c12083          	lw	ra,12(sp)
80005498:	00812403          	lw	s0,8(sp)
8000549c:	00412483          	lw	s1,4(sp)
800054a0:	00012903          	lw	s2,0(sp)
800054a4:	01010113          	addi	sp,sp,16
800054a8:	00008067          	ret

800054ac <install_trans>:
  for (tail = 0; tail < log.lh.n; tail++) {
800054ac:	0001b797          	auipc	a5,0x1b
800054b0:	9b47a783          	lw	a5,-1612(a5) # 8001fe60 <log+0x20>
800054b4:	0ef05863          	blez	a5,800055a4 <install_trans+0xf8>
{
800054b8:	fe010113          	addi	sp,sp,-32
800054bc:	00112e23          	sw	ra,28(sp)
800054c0:	00812c23          	sw	s0,24(sp)
800054c4:	00912a23          	sw	s1,20(sp)
800054c8:	01212823          	sw	s2,16(sp)
800054cc:	01312623          	sw	s3,12(sp)
800054d0:	01412423          	sw	s4,8(sp)
800054d4:	01512223          	sw	s5,4(sp)
800054d8:	01612023          	sw	s6,0(sp)
800054dc:	02010413          	addi	s0,sp,32
800054e0:	0001ba97          	auipc	s5,0x1b
800054e4:	984a8a93          	addi	s5,s5,-1660 # 8001fe64 <log+0x24>
  for (tail = 0; tail < log.lh.n; tail++) {
800054e8:	00000a13          	li	s4,0
    struct buf *lbuf = bread(log.dev, log.start+tail+1); // read log block
800054ec:	0001b997          	auipc	s3,0x1b
800054f0:	95498993          	addi	s3,s3,-1708 # 8001fe40 <log>
    memmove(dbuf->data, lbuf->data, BSIZE);  // copy block to dst
800054f4:	40000b13          	li	s6,1024
    struct buf *lbuf = bread(log.dev, log.start+tail+1); // read log block
800054f8:	00c9a583          	lw	a1,12(s3)
800054fc:	00ba05b3          	add	a1,s4,a1
80005500:	00158593          	addi	a1,a1,1
80005504:	01c9a503          	lw	a0,28(s3)
80005508:	fffff097          	auipc	ra,0xfffff
8000550c:	92c080e7          	jalr	-1748(ra) # 80003e34 <bread>
80005510:	00050913          	mv	s2,a0
    struct buf *dbuf = bread(log.dev, log.lh.block[tail]); // read dst
80005514:	000aa583          	lw	a1,0(s5)
80005518:	01c9a503          	lw	a0,28(s3)
8000551c:	fffff097          	auipc	ra,0xfffff
80005520:	918080e7          	jalr	-1768(ra) # 80003e34 <bread>
80005524:	00050493          	mv	s1,a0
    memmove(dbuf->data, lbuf->data, BSIZE);  // copy block to dst
80005528:	000b0613          	mv	a2,s6
8000552c:	03890593          	addi	a1,s2,56
80005530:	03850513          	addi	a0,a0,56
80005534:	ffffc097          	auipc	ra,0xffffc
80005538:	b28080e7          	jalr	-1240(ra) # 8000105c <memmove>
    bwrite(dbuf);  // write dst to disk
8000553c:	00048513          	mv	a0,s1
80005540:	fffff097          	auipc	ra,0xfffff
80005544:	a34080e7          	jalr	-1484(ra) # 80003f74 <bwrite>
    bunpin(dbuf);
80005548:	00048513          	mv	a0,s1
8000554c:	fffff097          	auipc	ra,0xfffff
80005550:	bac080e7          	jalr	-1108(ra) # 800040f8 <bunpin>
    brelse(lbuf);
80005554:	00090513          	mv	a0,s2
80005558:	fffff097          	auipc	ra,0xfffff
8000555c:	a78080e7          	jalr	-1416(ra) # 80003fd0 <brelse>
    brelse(dbuf);
80005560:	00048513          	mv	a0,s1
80005564:	fffff097          	auipc	ra,0xfffff
80005568:	a6c080e7          	jalr	-1428(ra) # 80003fd0 <brelse>
  for (tail = 0; tail < log.lh.n; tail++) {
8000556c:	001a0a13          	addi	s4,s4,1
80005570:	004a8a93          	addi	s5,s5,4
80005574:	0209a783          	lw	a5,32(s3)
80005578:	f8fa40e3          	blt	s4,a5,800054f8 <install_trans+0x4c>
}
8000557c:	01c12083          	lw	ra,28(sp)
80005580:	01812403          	lw	s0,24(sp)
80005584:	01412483          	lw	s1,20(sp)
80005588:	01012903          	lw	s2,16(sp)
8000558c:	00c12983          	lw	s3,12(sp)
80005590:	00812a03          	lw	s4,8(sp)
80005594:	00412a83          	lw	s5,4(sp)
80005598:	00012b03          	lw	s6,0(sp)
8000559c:	02010113          	addi	sp,sp,32
800055a0:	00008067          	ret
800055a4:	00008067          	ret

800055a8 <initlog>:
{
800055a8:	fe010113          	addi	sp,sp,-32
800055ac:	00112e23          	sw	ra,28(sp)
800055b0:	00812c23          	sw	s0,24(sp)
800055b4:	00912a23          	sw	s1,20(sp)
800055b8:	01212823          	sw	s2,16(sp)
800055bc:	01312623          	sw	s3,12(sp)
800055c0:	02010413          	addi	s0,sp,32
800055c4:	00050913          	mv	s2,a0
800055c8:	00058993          	mv	s3,a1
  initlock(&log.lock, "log");
800055cc:	0001b497          	auipc	s1,0x1b
800055d0:	87448493          	addi	s1,s1,-1932 # 8001fe40 <log>
800055d4:	00004597          	auipc	a1,0x4
800055d8:	fcc58593          	addi	a1,a1,-52 # 800095a0 <userret+0x500>
800055dc:	00048513          	mv	a0,s1
800055e0:	ffffb097          	auipc	ra,0xffffb
800055e4:	78c080e7          	jalr	1932(ra) # 80000d6c <initlock>
  log.start = sb->logstart;
800055e8:	0149a583          	lw	a1,20(s3)
800055ec:	00b4a623          	sw	a1,12(s1)
  log.size = sb->nlog;
800055f0:	0109a783          	lw	a5,16(s3)
800055f4:	00f4a823          	sw	a5,16(s1)
  log.dev = dev;
800055f8:	0124ae23          	sw	s2,28(s1)
  struct buf *buf = bread(log.dev, log.start);
800055fc:	00090513          	mv	a0,s2
80005600:	fffff097          	auipc	ra,0xfffff
80005604:	834080e7          	jalr	-1996(ra) # 80003e34 <bread>
  log.lh.n = lh->n;
80005608:	03852603          	lw	a2,56(a0)
8000560c:	02c4a023          	sw	a2,32(s1)
  for (i = 0; i < log.lh.n; i++) {
80005610:	02c05663          	blez	a2,8000563c <initlog+0x94>
80005614:	00050793          	mv	a5,a0
80005618:	0001b717          	auipc	a4,0x1b
8000561c:	84c70713          	addi	a4,a4,-1972 # 8001fe64 <log+0x24>
80005620:	00261613          	slli	a2,a2,0x2
80005624:	00a60633          	add	a2,a2,a0
    log.lh.block[i] = lh->block[i];
80005628:	03c7a683          	lw	a3,60(a5)
8000562c:	00d72023          	sw	a3,0(a4)
  for (i = 0; i < log.lh.n; i++) {
80005630:	00478793          	addi	a5,a5,4
80005634:	00470713          	addi	a4,a4,4
80005638:	fec798e3          	bne	a5,a2,80005628 <initlog+0x80>
  brelse(buf);
8000563c:	fffff097          	auipc	ra,0xfffff
80005640:	994080e7          	jalr	-1644(ra) # 80003fd0 <brelse>

static void
recover_from_log(void)
{
  read_head();
  install_trans(); // if committed, copy from log to disk
80005644:	00000097          	auipc	ra,0x0
80005648:	e68080e7          	jalr	-408(ra) # 800054ac <install_trans>
  log.lh.n = 0;
8000564c:	0001b797          	auipc	a5,0x1b
80005650:	8007aa23          	sw	zero,-2028(a5) # 8001fe60 <log+0x20>
  write_head(); // clear the log
80005654:	00000097          	auipc	ra,0x0
80005658:	dc0080e7          	jalr	-576(ra) # 80005414 <write_head>
}
8000565c:	01c12083          	lw	ra,28(sp)
80005660:	01812403          	lw	s0,24(sp)
80005664:	01412483          	lw	s1,20(sp)
80005668:	01012903          	lw	s2,16(sp)
8000566c:	00c12983          	lw	s3,12(sp)
80005670:	02010113          	addi	sp,sp,32
80005674:	00008067          	ret

80005678 <begin_op>:
}

// called at the start of each FS system call.
void
begin_op(void)
{
80005678:	ff010113          	addi	sp,sp,-16
8000567c:	00112623          	sw	ra,12(sp)
80005680:	00812423          	sw	s0,8(sp)
80005684:	00912223          	sw	s1,4(sp)
80005688:	01212023          	sw	s2,0(sp)
8000568c:	01010413          	addi	s0,sp,16
  acquire(&log.lock);
80005690:	0001a517          	auipc	a0,0x1a
80005694:	7b050513          	addi	a0,a0,1968 # 8001fe40 <log>
80005698:	ffffc097          	auipc	ra,0xffffc
8000569c:	864080e7          	jalr	-1948(ra) # 80000efc <acquire>
  while(1){
    if(log.committing){
800056a0:	0001a497          	auipc	s1,0x1a
800056a4:	7a048493          	addi	s1,s1,1952 # 8001fe40 <log>
      sleep(&log, &log.lock);
    } else if(log.lh.n + (log.outstanding+1)*MAXOPBLOCKS > LOGSIZE){
800056a8:	01e00913          	li	s2,30
800056ac:	0140006f          	j	800056c0 <begin_op+0x48>
      sleep(&log, &log.lock);
800056b0:	00048593          	mv	a1,s1
800056b4:	00048513          	mv	a0,s1
800056b8:	ffffd097          	auipc	ra,0xffffd
800056bc:	664080e7          	jalr	1636(ra) # 80002d1c <sleep>
    if(log.committing){
800056c0:	0184a783          	lw	a5,24(s1)
800056c4:	fe0796e3          	bnez	a5,800056b0 <begin_op+0x38>
    } else if(log.lh.n + (log.outstanding+1)*MAXOPBLOCKS > LOGSIZE){
800056c8:	0144a703          	lw	a4,20(s1)
800056cc:	00170713          	addi	a4,a4,1
800056d0:	00271793          	slli	a5,a4,0x2
800056d4:	00e787b3          	add	a5,a5,a4
800056d8:	00179793          	slli	a5,a5,0x1
800056dc:	0204a683          	lw	a3,32(s1)
800056e0:	00d787b3          	add	a5,a5,a3
800056e4:	00f95c63          	bge	s2,a5,800056fc <begin_op+0x84>
      // this op might exhaust log space; wait for commit.
      sleep(&log, &log.lock);
800056e8:	00048593          	mv	a1,s1
800056ec:	00048513          	mv	a0,s1
800056f0:	ffffd097          	auipc	ra,0xffffd
800056f4:	62c080e7          	jalr	1580(ra) # 80002d1c <sleep>
800056f8:	fc9ff06f          	j	800056c0 <begin_op+0x48>
    } else {
      log.outstanding += 1;
800056fc:	0001a797          	auipc	a5,0x1a
80005700:	74e7ac23          	sw	a4,1880(a5) # 8001fe54 <log+0x14>
      release(&log.lock);
80005704:	0001a517          	auipc	a0,0x1a
80005708:	73c50513          	addi	a0,a0,1852 # 8001fe40 <log>
8000570c:	ffffc097          	auipc	ra,0xffffc
80005710:	864080e7          	jalr	-1948(ra) # 80000f70 <release>
      break;
    }
  }
}
80005714:	00c12083          	lw	ra,12(sp)
80005718:	00812403          	lw	s0,8(sp)
8000571c:	00412483          	lw	s1,4(sp)
80005720:	00012903          	lw	s2,0(sp)
80005724:	01010113          	addi	sp,sp,16
80005728:	00008067          	ret

8000572c <end_op>:

// called at the end of each FS system call.
// commits if this was the last outstanding operation.
void
end_op(void)
{
8000572c:	fe010113          	addi	sp,sp,-32
80005730:	00112e23          	sw	ra,28(sp)
80005734:	00812c23          	sw	s0,24(sp)
80005738:	00912a23          	sw	s1,20(sp)
8000573c:	01212823          	sw	s2,16(sp)
80005740:	02010413          	addi	s0,sp,32
  int do_commit = 0;

  acquire(&log.lock);
80005744:	0001a917          	auipc	s2,0x1a
80005748:	6fc90913          	addi	s2,s2,1788 # 8001fe40 <log>
8000574c:	00090513          	mv	a0,s2
80005750:	ffffb097          	auipc	ra,0xffffb
80005754:	7ac080e7          	jalr	1964(ra) # 80000efc <acquire>
  log.outstanding -= 1;
80005758:	01492483          	lw	s1,20(s2)
8000575c:	fff48493          	addi	s1,s1,-1
80005760:	00992a23          	sw	s1,20(s2)
  if(log.committing)
80005764:	01892783          	lw	a5,24(s2)
80005768:	06079463          	bnez	a5,800057d0 <end_op+0xa4>
    panic("log.committing");
  if(log.outstanding == 0){
8000576c:	08049063          	bnez	s1,800057ec <end_op+0xc0>
    do_commit = 1;
    log.committing = 1;
80005770:	0001a917          	auipc	s2,0x1a
80005774:	6d090913          	addi	s2,s2,1744 # 8001fe40 <log>
80005778:	00100793          	li	a5,1
8000577c:	00f92c23          	sw	a5,24(s2)
    // begin_op() may be waiting for log space,
    // and decrementing log.outstanding has decreased
    // the amount of reserved space.
    wakeup(&log);
  }
  release(&log.lock);
80005780:	00090513          	mv	a0,s2
80005784:	ffffb097          	auipc	ra,0xffffb
80005788:	7ec080e7          	jalr	2028(ra) # 80000f70 <release>
}

static void
commit()
{
  if (log.lh.n > 0) {
8000578c:	02092783          	lw	a5,32(s2)
80005790:	08f04a63          	bgtz	a5,80005824 <end_op+0xf8>
    acquire(&log.lock);
80005794:	0001a517          	auipc	a0,0x1a
80005798:	6ac50513          	addi	a0,a0,1708 # 8001fe40 <log>
8000579c:	ffffb097          	auipc	ra,0xffffb
800057a0:	760080e7          	jalr	1888(ra) # 80000efc <acquire>
    log.committing = 0;
800057a4:	0001a797          	auipc	a5,0x1a
800057a8:	6a07aa23          	sw	zero,1716(a5) # 8001fe58 <log+0x18>
    wakeup(&log);
800057ac:	0001a517          	auipc	a0,0x1a
800057b0:	69450513          	addi	a0,a0,1684 # 8001fe40 <log>
800057b4:	ffffd097          	auipc	ra,0xffffd
800057b8:	778080e7          	jalr	1912(ra) # 80002f2c <wakeup>
    release(&log.lock);
800057bc:	0001a517          	auipc	a0,0x1a
800057c0:	68450513          	addi	a0,a0,1668 # 8001fe40 <log>
800057c4:	ffffb097          	auipc	ra,0xffffb
800057c8:	7ac080e7          	jalr	1964(ra) # 80000f70 <release>
}
800057cc:	0400006f          	j	8000580c <end_op+0xe0>
800057d0:	01312623          	sw	s3,12(sp)
800057d4:	01412423          	sw	s4,8(sp)
800057d8:	01512223          	sw	s5,4(sp)
    panic("log.committing");
800057dc:	00004517          	auipc	a0,0x4
800057e0:	dc850513          	addi	a0,a0,-568 # 800095a4 <userret+0x504>
800057e4:	ffffb097          	auipc	ra,0xffffb
800057e8:	f18080e7          	jalr	-232(ra) # 800006fc <panic>
    wakeup(&log);
800057ec:	0001a517          	auipc	a0,0x1a
800057f0:	65450513          	addi	a0,a0,1620 # 8001fe40 <log>
800057f4:	ffffd097          	auipc	ra,0xffffd
800057f8:	738080e7          	jalr	1848(ra) # 80002f2c <wakeup>
  release(&log.lock);
800057fc:	0001a517          	auipc	a0,0x1a
80005800:	64450513          	addi	a0,a0,1604 # 8001fe40 <log>
80005804:	ffffb097          	auipc	ra,0xffffb
80005808:	76c080e7          	jalr	1900(ra) # 80000f70 <release>
}
8000580c:	01c12083          	lw	ra,28(sp)
80005810:	01812403          	lw	s0,24(sp)
80005814:	01412483          	lw	s1,20(sp)
80005818:	01012903          	lw	s2,16(sp)
8000581c:	02010113          	addi	sp,sp,32
80005820:	00008067          	ret
80005824:	01312623          	sw	s3,12(sp)
80005828:	01412423          	sw	s4,8(sp)
8000582c:	01512223          	sw	s5,4(sp)
  for (tail = 0; tail < log.lh.n; tail++) {
80005830:	0001aa97          	auipc	s5,0x1a
80005834:	634a8a93          	addi	s5,s5,1588 # 8001fe64 <log+0x24>
    struct buf *to = bread(log.dev, log.start+tail+1); // log block
80005838:	0001aa17          	auipc	s4,0x1a
8000583c:	608a0a13          	addi	s4,s4,1544 # 8001fe40 <log>
80005840:	00ca2583          	lw	a1,12(s4)
80005844:	00b485b3          	add	a1,s1,a1
80005848:	00158593          	addi	a1,a1,1
8000584c:	01ca2503          	lw	a0,28(s4)
80005850:	ffffe097          	auipc	ra,0xffffe
80005854:	5e4080e7          	jalr	1508(ra) # 80003e34 <bread>
80005858:	00050913          	mv	s2,a0
    struct buf *from = bread(log.dev, log.lh.block[tail]); // cache block
8000585c:	000aa583          	lw	a1,0(s5)
80005860:	01ca2503          	lw	a0,28(s4)
80005864:	ffffe097          	auipc	ra,0xffffe
80005868:	5d0080e7          	jalr	1488(ra) # 80003e34 <bread>
8000586c:	00050993          	mv	s3,a0
    memmove(to->data, from->data, BSIZE);
80005870:	40000613          	li	a2,1024
80005874:	03850593          	addi	a1,a0,56
80005878:	03890513          	addi	a0,s2,56
8000587c:	ffffb097          	auipc	ra,0xffffb
80005880:	7e0080e7          	jalr	2016(ra) # 8000105c <memmove>
    bwrite(to);  // write the log
80005884:	00090513          	mv	a0,s2
80005888:	ffffe097          	auipc	ra,0xffffe
8000588c:	6ec080e7          	jalr	1772(ra) # 80003f74 <bwrite>
    brelse(from);
80005890:	00098513          	mv	a0,s3
80005894:	ffffe097          	auipc	ra,0xffffe
80005898:	73c080e7          	jalr	1852(ra) # 80003fd0 <brelse>
    brelse(to);
8000589c:	00090513          	mv	a0,s2
800058a0:	ffffe097          	auipc	ra,0xffffe
800058a4:	730080e7          	jalr	1840(ra) # 80003fd0 <brelse>
  for (tail = 0; tail < log.lh.n; tail++) {
800058a8:	00148493          	addi	s1,s1,1
800058ac:	004a8a93          	addi	s5,s5,4
800058b0:	020a2783          	lw	a5,32(s4)
800058b4:	f8f4c6e3          	blt	s1,a5,80005840 <end_op+0x114>
    write_log();     // Write modified blocks from cache to log
    write_head();    // Write header to disk -- the real commit
800058b8:	00000097          	auipc	ra,0x0
800058bc:	b5c080e7          	jalr	-1188(ra) # 80005414 <write_head>
    install_trans(); // Now install writes to home locations
800058c0:	00000097          	auipc	ra,0x0
800058c4:	bec080e7          	jalr	-1044(ra) # 800054ac <install_trans>
    log.lh.n = 0;
800058c8:	0001a797          	auipc	a5,0x1a
800058cc:	5807ac23          	sw	zero,1432(a5) # 8001fe60 <log+0x20>
    write_head();    // Erase the transaction from the log
800058d0:	00000097          	auipc	ra,0x0
800058d4:	b44080e7          	jalr	-1212(ra) # 80005414 <write_head>
800058d8:	00c12983          	lw	s3,12(sp)
800058dc:	00812a03          	lw	s4,8(sp)
800058e0:	00412a83          	lw	s5,4(sp)
800058e4:	eb1ff06f          	j	80005794 <end_op+0x68>

800058e8 <log_write>:
//   modify bp->data[]
//   log_write(bp)
//   brelse(bp)
void
log_write(struct buf *b)
{
800058e8:	ff010113          	addi	sp,sp,-16
800058ec:	00112623          	sw	ra,12(sp)
800058f0:	00812423          	sw	s0,8(sp)
800058f4:	00912223          	sw	s1,4(sp)
800058f8:	01010413          	addi	s0,sp,16
  int i;

  if (log.lh.n >= LOGSIZE || log.lh.n >= log.size - 1)
800058fc:	0001a717          	auipc	a4,0x1a
80005900:	56472703          	lw	a4,1380(a4) # 8001fe60 <log+0x20>
80005904:	01d00793          	li	a5,29
80005908:	0ae7c263          	blt	a5,a4,800059ac <log_write+0xc4>
8000590c:	00050493          	mv	s1,a0
80005910:	0001a797          	auipc	a5,0x1a
80005914:	5407a783          	lw	a5,1344(a5) # 8001fe50 <log+0x10>
80005918:	fff78793          	addi	a5,a5,-1
8000591c:	08f75863          	bge	a4,a5,800059ac <log_write+0xc4>
    panic("too big a transaction");
  if (log.outstanding < 1)
80005920:	0001a797          	auipc	a5,0x1a
80005924:	5347a783          	lw	a5,1332(a5) # 8001fe54 <log+0x14>
80005928:	08f05a63          	blez	a5,800059bc <log_write+0xd4>
    panic("log_write outside of trans");

  acquire(&log.lock);
8000592c:	0001a517          	auipc	a0,0x1a
80005930:	51450513          	addi	a0,a0,1300 # 8001fe40 <log>
80005934:	ffffb097          	auipc	ra,0xffffb
80005938:	5c8080e7          	jalr	1480(ra) # 80000efc <acquire>
  for (i = 0; i < log.lh.n; i++) {
8000593c:	0001a617          	auipc	a2,0x1a
80005940:	52462603          	lw	a2,1316(a2) # 8001fe60 <log+0x20>
80005944:	08c05463          	blez	a2,800059cc <log_write+0xe4>
    if (log.lh.block[i] == b->blockno)   // log absorbtion
80005948:	00c4a583          	lw	a1,12(s1)
8000594c:	0001a717          	auipc	a4,0x1a
80005950:	51870713          	addi	a4,a4,1304 # 8001fe64 <log+0x24>
  for (i = 0; i < log.lh.n; i++) {
80005954:	00000793          	li	a5,0
    if (log.lh.block[i] == b->blockno)   // log absorbtion
80005958:	00072683          	lw	a3,0(a4)
8000595c:	06b68a63          	beq	a3,a1,800059d0 <log_write+0xe8>
  for (i = 0; i < log.lh.n; i++) {
80005960:	00178793          	addi	a5,a5,1
80005964:	00470713          	addi	a4,a4,4
80005968:	fec798e3          	bne	a5,a2,80005958 <log_write+0x70>
      break;
  }
  log.lh.block[i] = b->blockno;
8000596c:	00860613          	addi	a2,a2,8
80005970:	00261613          	slli	a2,a2,0x2
80005974:	0001a797          	auipc	a5,0x1a
80005978:	4cc78793          	addi	a5,a5,1228 # 8001fe40 <log>
8000597c:	00c787b3          	add	a5,a5,a2
80005980:	00c4a703          	lw	a4,12(s1)
80005984:	00e7a223          	sw	a4,4(a5)
  if (i == log.lh.n) {  // Add new block to log?
    bpin(b);
80005988:	00048513          	mv	a0,s1
8000598c:	ffffe097          	auipc	ra,0xffffe
80005990:	714080e7          	jalr	1812(ra) # 800040a0 <bpin>
    log.lh.n++;
80005994:	0001a717          	auipc	a4,0x1a
80005998:	4ac70713          	addi	a4,a4,1196 # 8001fe40 <log>
8000599c:	02072783          	lw	a5,32(a4)
800059a0:	00178793          	addi	a5,a5,1
800059a4:	02f72023          	sw	a5,32(a4)
800059a8:	0480006f          	j	800059f0 <log_write+0x108>
    panic("too big a transaction");
800059ac:	00004517          	auipc	a0,0x4
800059b0:	c0850513          	addi	a0,a0,-1016 # 800095b4 <userret+0x514>
800059b4:	ffffb097          	auipc	ra,0xffffb
800059b8:	d48080e7          	jalr	-696(ra) # 800006fc <panic>
    panic("log_write outside of trans");
800059bc:	00004517          	auipc	a0,0x4
800059c0:	c1050513          	addi	a0,a0,-1008 # 800095cc <userret+0x52c>
800059c4:	ffffb097          	auipc	ra,0xffffb
800059c8:	d38080e7          	jalr	-712(ra) # 800006fc <panic>
  for (i = 0; i < log.lh.n; i++) {
800059cc:	00000793          	li	a5,0
  log.lh.block[i] = b->blockno;
800059d0:	00878693          	addi	a3,a5,8
800059d4:	00269693          	slli	a3,a3,0x2
800059d8:	0001a717          	auipc	a4,0x1a
800059dc:	46870713          	addi	a4,a4,1128 # 8001fe40 <log>
800059e0:	00d70733          	add	a4,a4,a3
800059e4:	00c4a683          	lw	a3,12(s1)
800059e8:	00d72223          	sw	a3,4(a4)
  if (i == log.lh.n) {  // Add new block to log?
800059ec:	f8f60ee3          	beq	a2,a5,80005988 <log_write+0xa0>
  }
  release(&log.lock);
800059f0:	0001a517          	auipc	a0,0x1a
800059f4:	45050513          	addi	a0,a0,1104 # 8001fe40 <log>
800059f8:	ffffb097          	auipc	ra,0xffffb
800059fc:	578080e7          	jalr	1400(ra) # 80000f70 <release>
}
80005a00:	00c12083          	lw	ra,12(sp)
80005a04:	00812403          	lw	s0,8(sp)
80005a08:	00412483          	lw	s1,4(sp)
80005a0c:	01010113          	addi	sp,sp,16
80005a10:	00008067          	ret

80005a14 <initsleeplock>:
#include "proc.h"
#include "sleeplock.h"

void
initsleeplock(struct sleeplock *lk, char *name)
{
80005a14:	ff010113          	addi	sp,sp,-16
80005a18:	00112623          	sw	ra,12(sp)
80005a1c:	00812423          	sw	s0,8(sp)
80005a20:	00912223          	sw	s1,4(sp)
80005a24:	01212023          	sw	s2,0(sp)
80005a28:	01010413          	addi	s0,sp,16
80005a2c:	00050493          	mv	s1,a0
80005a30:	00058913          	mv	s2,a1
  initlock(&lk->lk, "sleep lock");
80005a34:	00004597          	auipc	a1,0x4
80005a38:	bb458593          	addi	a1,a1,-1100 # 800095e8 <userret+0x548>
80005a3c:	00450513          	addi	a0,a0,4
80005a40:	ffffb097          	auipc	ra,0xffffb
80005a44:	32c080e7          	jalr	812(ra) # 80000d6c <initlock>
  lk->name = name;
80005a48:	0124a823          	sw	s2,16(s1)
  lk->locked = 0;
80005a4c:	0004a023          	sw	zero,0(s1)
  lk->pid = 0;
80005a50:	0004aa23          	sw	zero,20(s1)
}
80005a54:	00c12083          	lw	ra,12(sp)
80005a58:	00812403          	lw	s0,8(sp)
80005a5c:	00412483          	lw	s1,4(sp)
80005a60:	00012903          	lw	s2,0(sp)
80005a64:	01010113          	addi	sp,sp,16
80005a68:	00008067          	ret

80005a6c <acquiresleep>:

void
acquiresleep(struct sleeplock *lk)
{
80005a6c:	ff010113          	addi	sp,sp,-16
80005a70:	00112623          	sw	ra,12(sp)
80005a74:	00812423          	sw	s0,8(sp)
80005a78:	00912223          	sw	s1,4(sp)
80005a7c:	01212023          	sw	s2,0(sp)
80005a80:	01010413          	addi	s0,sp,16
80005a84:	00050493          	mv	s1,a0
  acquire(&lk->lk);
80005a88:	00450913          	addi	s2,a0,4
80005a8c:	00090513          	mv	a0,s2
80005a90:	ffffb097          	auipc	ra,0xffffb
80005a94:	46c080e7          	jalr	1132(ra) # 80000efc <acquire>
  while (lk->locked) {
80005a98:	0004a783          	lw	a5,0(s1)
80005a9c:	00078e63          	beqz	a5,80005ab8 <acquiresleep+0x4c>
    sleep(lk, &lk->lk);
80005aa0:	00090593          	mv	a1,s2
80005aa4:	00048513          	mv	a0,s1
80005aa8:	ffffd097          	auipc	ra,0xffffd
80005aac:	274080e7          	jalr	628(ra) # 80002d1c <sleep>
  while (lk->locked) {
80005ab0:	0004a783          	lw	a5,0(s1)
80005ab4:	fe0796e3          	bnez	a5,80005aa0 <acquiresleep+0x34>
  }
  lk->locked = 1;
80005ab8:	00100793          	li	a5,1
80005abc:	00f4a023          	sw	a5,0(s1)
  lk->pid = myproc()->pid;
80005ac0:	ffffd097          	auipc	ra,0xffffd
80005ac4:	81c080e7          	jalr	-2020(ra) # 800022dc <myproc>
80005ac8:	02052783          	lw	a5,32(a0)
80005acc:	00f4aa23          	sw	a5,20(s1)
  release(&lk->lk);
80005ad0:	00090513          	mv	a0,s2
80005ad4:	ffffb097          	auipc	ra,0xffffb
80005ad8:	49c080e7          	jalr	1180(ra) # 80000f70 <release>
}
80005adc:	00c12083          	lw	ra,12(sp)
80005ae0:	00812403          	lw	s0,8(sp)
80005ae4:	00412483          	lw	s1,4(sp)
80005ae8:	00012903          	lw	s2,0(sp)
80005aec:	01010113          	addi	sp,sp,16
80005af0:	00008067          	ret

80005af4 <releasesleep>:

void
releasesleep(struct sleeplock *lk)
{
80005af4:	ff010113          	addi	sp,sp,-16
80005af8:	00112623          	sw	ra,12(sp)
80005afc:	00812423          	sw	s0,8(sp)
80005b00:	00912223          	sw	s1,4(sp)
80005b04:	01212023          	sw	s2,0(sp)
80005b08:	01010413          	addi	s0,sp,16
80005b0c:	00050493          	mv	s1,a0
  acquire(&lk->lk);
80005b10:	00450913          	addi	s2,a0,4
80005b14:	00090513          	mv	a0,s2
80005b18:	ffffb097          	auipc	ra,0xffffb
80005b1c:	3e4080e7          	jalr	996(ra) # 80000efc <acquire>
  lk->locked = 0;
80005b20:	0004a023          	sw	zero,0(s1)
  lk->pid = 0;
80005b24:	0004aa23          	sw	zero,20(s1)
  wakeup(lk);
80005b28:	00048513          	mv	a0,s1
80005b2c:	ffffd097          	auipc	ra,0xffffd
80005b30:	400080e7          	jalr	1024(ra) # 80002f2c <wakeup>
  release(&lk->lk);
80005b34:	00090513          	mv	a0,s2
80005b38:	ffffb097          	auipc	ra,0xffffb
80005b3c:	438080e7          	jalr	1080(ra) # 80000f70 <release>
}
80005b40:	00c12083          	lw	ra,12(sp)
80005b44:	00812403          	lw	s0,8(sp)
80005b48:	00412483          	lw	s1,4(sp)
80005b4c:	00012903          	lw	s2,0(sp)
80005b50:	01010113          	addi	sp,sp,16
80005b54:	00008067          	ret

80005b58 <holdingsleep>:

int
holdingsleep(struct sleeplock *lk)
{
80005b58:	fe010113          	addi	sp,sp,-32
80005b5c:	00112e23          	sw	ra,28(sp)
80005b60:	00812c23          	sw	s0,24(sp)
80005b64:	00912a23          	sw	s1,20(sp)
80005b68:	01212823          	sw	s2,16(sp)
80005b6c:	02010413          	addi	s0,sp,32
80005b70:	00050493          	mv	s1,a0
  int r;
  
  acquire(&lk->lk);
80005b74:	00450913          	addi	s2,a0,4
80005b78:	00090513          	mv	a0,s2
80005b7c:	ffffb097          	auipc	ra,0xffffb
80005b80:	380080e7          	jalr	896(ra) # 80000efc <acquire>
  r = lk->locked && (lk->pid == myproc()->pid);
80005b84:	0004a783          	lw	a5,0(s1)
80005b88:	02079863          	bnez	a5,80005bb8 <holdingsleep+0x60>
80005b8c:	00000493          	li	s1,0
  release(&lk->lk);
80005b90:	00090513          	mv	a0,s2
80005b94:	ffffb097          	auipc	ra,0xffffb
80005b98:	3dc080e7          	jalr	988(ra) # 80000f70 <release>
  return r;
}
80005b9c:	00048513          	mv	a0,s1
80005ba0:	01c12083          	lw	ra,28(sp)
80005ba4:	01812403          	lw	s0,24(sp)
80005ba8:	01412483          	lw	s1,20(sp)
80005bac:	01012903          	lw	s2,16(sp)
80005bb0:	02010113          	addi	sp,sp,32
80005bb4:	00008067          	ret
80005bb8:	01312623          	sw	s3,12(sp)
  r = lk->locked && (lk->pid == myproc()->pid);
80005bbc:	0144a783          	lw	a5,20(s1)
80005bc0:	00078993          	mv	s3,a5
80005bc4:	ffffc097          	auipc	ra,0xffffc
80005bc8:	718080e7          	jalr	1816(ra) # 800022dc <myproc>
80005bcc:	02052483          	lw	s1,32(a0)
80005bd0:	413484b3          	sub	s1,s1,s3
80005bd4:	0014b493          	seqz	s1,s1
80005bd8:	00c12983          	lw	s3,12(sp)
80005bdc:	fb5ff06f          	j	80005b90 <holdingsleep+0x38>

80005be0 <fileinit>:
  struct file file[NFILE];
} ftable;

void
fileinit(void)
{
80005be0:	ff010113          	addi	sp,sp,-16
80005be4:	00112623          	sw	ra,12(sp)
80005be8:	00812423          	sw	s0,8(sp)
80005bec:	01010413          	addi	s0,sp,16
  initlock(&ftable.lock, "ftable");
80005bf0:	00004597          	auipc	a1,0x4
80005bf4:	a0458593          	addi	a1,a1,-1532 # 800095f4 <userret+0x554>
80005bf8:	0001a517          	auipc	a0,0x1a
80005bfc:	33450513          	addi	a0,a0,820 # 8001ff2c <ftable>
80005c00:	ffffb097          	auipc	ra,0xffffb
80005c04:	16c080e7          	jalr	364(ra) # 80000d6c <initlock>
}
80005c08:	00c12083          	lw	ra,12(sp)
80005c0c:	00812403          	lw	s0,8(sp)
80005c10:	01010113          	addi	sp,sp,16
80005c14:	00008067          	ret

80005c18 <filealloc>:

// Allocate a file structure.
struct file*
filealloc(void)
{
80005c18:	ff010113          	addi	sp,sp,-16
80005c1c:	00112623          	sw	ra,12(sp)
80005c20:	00812423          	sw	s0,8(sp)
80005c24:	00912223          	sw	s1,4(sp)
80005c28:	01010413          	addi	s0,sp,16
  struct file *f;

  acquire(&ftable.lock);
80005c2c:	0001a517          	auipc	a0,0x1a
80005c30:	30050513          	addi	a0,a0,768 # 8001ff2c <ftable>
80005c34:	ffffb097          	auipc	ra,0xffffb
80005c38:	2c8080e7          	jalr	712(ra) # 80000efc <acquire>
  for(f = ftable.file; f < ftable.file + NFILE; f++){
80005c3c:	0001a497          	auipc	s1,0x1a
80005c40:	2fc48493          	addi	s1,s1,764 # 8001ff38 <ftable+0xc>
80005c44:	0001b717          	auipc	a4,0x1b
80005c48:	de470713          	addi	a4,a4,-540 # 80020a28 <ftable+0xafc>
    if(f->ref == 0){
80005c4c:	0044a783          	lw	a5,4(s1)
80005c50:	02078263          	beqz	a5,80005c74 <filealloc+0x5c>
  for(f = ftable.file; f < ftable.file + NFILE; f++){
80005c54:	01c48493          	addi	s1,s1,28
80005c58:	fee49ae3          	bne	s1,a4,80005c4c <filealloc+0x34>
      f->ref = 1;
      release(&ftable.lock);
      return f;
    }
  }
  release(&ftable.lock);
80005c5c:	0001a517          	auipc	a0,0x1a
80005c60:	2d050513          	addi	a0,a0,720 # 8001ff2c <ftable>
80005c64:	ffffb097          	auipc	ra,0xffffb
80005c68:	30c080e7          	jalr	780(ra) # 80000f70 <release>
  return 0;
80005c6c:	00000493          	li	s1,0
80005c70:	01c0006f          	j	80005c8c <filealloc+0x74>
      f->ref = 1;
80005c74:	00100793          	li	a5,1
80005c78:	00f4a223          	sw	a5,4(s1)
      release(&ftable.lock);
80005c7c:	0001a517          	auipc	a0,0x1a
80005c80:	2b050513          	addi	a0,a0,688 # 8001ff2c <ftable>
80005c84:	ffffb097          	auipc	ra,0xffffb
80005c88:	2ec080e7          	jalr	748(ra) # 80000f70 <release>
}
80005c8c:	00048513          	mv	a0,s1
80005c90:	00c12083          	lw	ra,12(sp)
80005c94:	00812403          	lw	s0,8(sp)
80005c98:	00412483          	lw	s1,4(sp)
80005c9c:	01010113          	addi	sp,sp,16
80005ca0:	00008067          	ret

80005ca4 <filedup>:

// Increment ref count for file f.
struct file*
filedup(struct file *f)
{
80005ca4:	ff010113          	addi	sp,sp,-16
80005ca8:	00112623          	sw	ra,12(sp)
80005cac:	00812423          	sw	s0,8(sp)
80005cb0:	00912223          	sw	s1,4(sp)
80005cb4:	01010413          	addi	s0,sp,16
80005cb8:	00050493          	mv	s1,a0
  acquire(&ftable.lock);
80005cbc:	0001a517          	auipc	a0,0x1a
80005cc0:	27050513          	addi	a0,a0,624 # 8001ff2c <ftable>
80005cc4:	ffffb097          	auipc	ra,0xffffb
80005cc8:	238080e7          	jalr	568(ra) # 80000efc <acquire>
  if(f->ref < 1)
80005ccc:	0044a783          	lw	a5,4(s1)
80005cd0:	02f05a63          	blez	a5,80005d04 <filedup+0x60>
    panic("filedup");
  f->ref++;
80005cd4:	00178793          	addi	a5,a5,1
80005cd8:	00f4a223          	sw	a5,4(s1)
  release(&ftable.lock);
80005cdc:	0001a517          	auipc	a0,0x1a
80005ce0:	25050513          	addi	a0,a0,592 # 8001ff2c <ftable>
80005ce4:	ffffb097          	auipc	ra,0xffffb
80005ce8:	28c080e7          	jalr	652(ra) # 80000f70 <release>
  return f;
}
80005cec:	00048513          	mv	a0,s1
80005cf0:	00c12083          	lw	ra,12(sp)
80005cf4:	00812403          	lw	s0,8(sp)
80005cf8:	00412483          	lw	s1,4(sp)
80005cfc:	01010113          	addi	sp,sp,16
80005d00:	00008067          	ret
    panic("filedup");
80005d04:	00004517          	auipc	a0,0x4
80005d08:	8f850513          	addi	a0,a0,-1800 # 800095fc <userret+0x55c>
80005d0c:	ffffb097          	auipc	ra,0xffffb
80005d10:	9f0080e7          	jalr	-1552(ra) # 800006fc <panic>

80005d14 <fileclose>:

// Close file f.  (Decrement ref count, close when reaches 0.)
void
fileclose(struct file *f)
{
80005d14:	fe010113          	addi	sp,sp,-32
80005d18:	00112e23          	sw	ra,28(sp)
80005d1c:	00812c23          	sw	s0,24(sp)
80005d20:	00912a23          	sw	s1,20(sp)
80005d24:	02010413          	addi	s0,sp,32
80005d28:	00050493          	mv	s1,a0
  struct file ff;

  acquire(&ftable.lock);
80005d2c:	0001a517          	auipc	a0,0x1a
80005d30:	20050513          	addi	a0,a0,512 # 8001ff2c <ftable>
80005d34:	ffffb097          	auipc	ra,0xffffb
80005d38:	1c8080e7          	jalr	456(ra) # 80000efc <acquire>
  if(f->ref < 1)
80005d3c:	0044a783          	lw	a5,4(s1)
80005d40:	08f05063          	blez	a5,80005dc0 <fileclose+0xac>
    panic("fileclose");
  if(--f->ref > 0){
80005d44:	fff78793          	addi	a5,a5,-1
80005d48:	00f4a223          	sw	a5,4(s1)
80005d4c:	08f04a63          	bgtz	a5,80005de0 <fileclose+0xcc>
80005d50:	01212823          	sw	s2,16(sp)
80005d54:	01312623          	sw	s3,12(sp)
80005d58:	01412423          	sw	s4,8(sp)
80005d5c:	01512223          	sw	s5,4(sp)
    release(&ftable.lock);
    return;
  }
  ff = *f;
80005d60:	0004a783          	lw	a5,0(s1)
80005d64:	00078913          	mv	s2,a5
80005d68:	0094c783          	lbu	a5,9(s1)
80005d6c:	00078993          	mv	s3,a5
80005d70:	00c4a783          	lw	a5,12(s1)
80005d74:	00078a13          	mv	s4,a5
80005d78:	0104a783          	lw	a5,16(s1)
80005d7c:	00078a93          	mv	s5,a5
  f->ref = 0;
80005d80:	0004a223          	sw	zero,4(s1)
  f->type = FD_NONE;
80005d84:	0004a023          	sw	zero,0(s1)
  release(&ftable.lock);
80005d88:	0001a517          	auipc	a0,0x1a
80005d8c:	1a450513          	addi	a0,a0,420 # 8001ff2c <ftable>
80005d90:	ffffb097          	auipc	ra,0xffffb
80005d94:	1e0080e7          	jalr	480(ra) # 80000f70 <release>

  if(ff.type == FD_PIPE){
80005d98:	00100793          	li	a5,1
80005d9c:	06f90463          	beq	s2,a5,80005e04 <fileclose+0xf0>
    pipeclose(ff.pipe, ff.writable);
  } else if(ff.type == FD_INODE || ff.type == FD_DEVICE){
80005da0:	ffe90793          	addi	a5,s2,-2
80005da4:	00100713          	li	a4,1
80005da8:	08f77063          	bgeu	a4,a5,80005e28 <fileclose+0x114>
80005dac:	01012903          	lw	s2,16(sp)
80005db0:	00c12983          	lw	s3,12(sp)
80005db4:	00812a03          	lw	s4,8(sp)
80005db8:	00412a83          	lw	s5,4(sp)
80005dbc:	0340006f          	j	80005df0 <fileclose+0xdc>
80005dc0:	01212823          	sw	s2,16(sp)
80005dc4:	01312623          	sw	s3,12(sp)
80005dc8:	01412423          	sw	s4,8(sp)
80005dcc:	01512223          	sw	s5,4(sp)
    panic("fileclose");
80005dd0:	00004517          	auipc	a0,0x4
80005dd4:	83450513          	addi	a0,a0,-1996 # 80009604 <userret+0x564>
80005dd8:	ffffb097          	auipc	ra,0xffffb
80005ddc:	924080e7          	jalr	-1756(ra) # 800006fc <panic>
    release(&ftable.lock);
80005de0:	0001a517          	auipc	a0,0x1a
80005de4:	14c50513          	addi	a0,a0,332 # 8001ff2c <ftable>
80005de8:	ffffb097          	auipc	ra,0xffffb
80005dec:	188080e7          	jalr	392(ra) # 80000f70 <release>
    begin_op();
    iput(ff.ip);
    end_op();
  }
}
80005df0:	01c12083          	lw	ra,28(sp)
80005df4:	01812403          	lw	s0,24(sp)
80005df8:	01412483          	lw	s1,20(sp)
80005dfc:	02010113          	addi	sp,sp,32
80005e00:	00008067          	ret
    pipeclose(ff.pipe, ff.writable);
80005e04:	00098593          	mv	a1,s3
80005e08:	000a0513          	mv	a0,s4
80005e0c:	00000097          	auipc	ra,0x0
80005e10:	588080e7          	jalr	1416(ra) # 80006394 <pipeclose>
80005e14:	01012903          	lw	s2,16(sp)
80005e18:	00c12983          	lw	s3,12(sp)
80005e1c:	00812a03          	lw	s4,8(sp)
80005e20:	00412a83          	lw	s5,4(sp)
80005e24:	fcdff06f          	j	80005df0 <fileclose+0xdc>
    begin_op();
80005e28:	00000097          	auipc	ra,0x0
80005e2c:	850080e7          	jalr	-1968(ra) # 80005678 <begin_op>
    iput(ff.ip);
80005e30:	000a8513          	mv	a0,s5
80005e34:	fffff097          	auipc	ra,0xfffff
80005e38:	c00080e7          	jalr	-1024(ra) # 80004a34 <iput>
    end_op();
80005e3c:	00000097          	auipc	ra,0x0
80005e40:	8f0080e7          	jalr	-1808(ra) # 8000572c <end_op>
80005e44:	01012903          	lw	s2,16(sp)
80005e48:	00c12983          	lw	s3,12(sp)
80005e4c:	00812a03          	lw	s4,8(sp)
80005e50:	00412a83          	lw	s5,4(sp)
80005e54:	f9dff06f          	j	80005df0 <fileclose+0xdc>

80005e58 <filestat>:

// Get metadata about file f.
// addr is a user virtual address, pointing to a struct stat.
int
filestat(struct file *f, uint32 addr)
{
80005e58:	fc010113          	addi	sp,sp,-64
80005e5c:	02112e23          	sw	ra,60(sp)
80005e60:	02812c23          	sw	s0,56(sp)
80005e64:	02912a23          	sw	s1,52(sp)
80005e68:	03412423          	sw	s4,40(sp)
80005e6c:	04010413          	addi	s0,sp,64
80005e70:	00050493          	mv	s1,a0
80005e74:	00058a13          	mv	s4,a1
  struct proc *p = myproc();
80005e78:	ffffc097          	auipc	ra,0xffffc
80005e7c:	464080e7          	jalr	1124(ra) # 800022dc <myproc>
  struct stat st;
  
  if(f->type == FD_INODE || f->type == FD_DEVICE){
80005e80:	0004a783          	lw	a5,0(s1)
80005e84:	ffe78793          	addi	a5,a5,-2
80005e88:	00100713          	li	a4,1
80005e8c:	06f76c63          	bltu	a4,a5,80005f04 <filestat+0xac>
80005e90:	03212823          	sw	s2,48(sp)
80005e94:	03312623          	sw	s3,44(sp)
80005e98:	00050993          	mv	s3,a0
    ilock(f->ip);
80005e9c:	0104a503          	lw	a0,16(s1)
80005ea0:	fffff097          	auipc	ra,0xfffff
80005ea4:	a18080e7          	jalr	-1512(ra) # 800048b8 <ilock>
    stati(f->ip, &st);
80005ea8:	fc840913          	addi	s2,s0,-56
80005eac:	00090593          	mv	a1,s2
80005eb0:	0104a503          	lw	a0,16(s1)
80005eb4:	fffff097          	auipc	ra,0xfffff
80005eb8:	d54080e7          	jalr	-684(ra) # 80004c08 <stati>
    iunlock(f->ip);
80005ebc:	0104a503          	lw	a0,16(s1)
80005ec0:	fffff097          	auipc	ra,0xfffff
80005ec4:	b04080e7          	jalr	-1276(ra) # 800049c4 <iunlock>
    if(copyout(p->pagetable, addr, (char *)&st, sizeof(st)) < 0)
80005ec8:	01800693          	li	a3,24
80005ecc:	00090613          	mv	a2,s2
80005ed0:	000a0593          	mv	a1,s4
80005ed4:	02c9a503          	lw	a0,44(s3)
80005ed8:	ffffc097          	auipc	ra,0xffffc
80005edc:	f24080e7          	jalr	-220(ra) # 80001dfc <copyout>
80005ee0:	41f55513          	srai	a0,a0,0x1f
80005ee4:	03012903          	lw	s2,48(sp)
80005ee8:	02c12983          	lw	s3,44(sp)
      return -1;
    return 0;
  }
  return -1;
}
80005eec:	03c12083          	lw	ra,60(sp)
80005ef0:	03812403          	lw	s0,56(sp)
80005ef4:	03412483          	lw	s1,52(sp)
80005ef8:	02812a03          	lw	s4,40(sp)
80005efc:	04010113          	addi	sp,sp,64
80005f00:	00008067          	ret
  return -1;
80005f04:	fff00513          	li	a0,-1
80005f08:	fe5ff06f          	j	80005eec <filestat+0x94>

80005f0c <fileread>:

// Read from file f.
// addr is a user virtual address.
int
fileread(struct file *f, uint32 addr, int n)
{
80005f0c:	fe010113          	addi	sp,sp,-32
80005f10:	00112e23          	sw	ra,28(sp)
80005f14:	00812c23          	sw	s0,24(sp)
80005f18:	01212823          	sw	s2,16(sp)
80005f1c:	02010413          	addi	s0,sp,32
  int r = 0;

  if(f->readable == 0)
80005f20:	00854783          	lbu	a5,8(a0)
80005f24:	10078663          	beqz	a5,80006030 <fileread+0x124>
80005f28:	00912a23          	sw	s1,20(sp)
80005f2c:	01312623          	sw	s3,12(sp)
80005f30:	00050493          	mv	s1,a0
80005f34:	00058913          	mv	s2,a1
80005f38:	00060993          	mv	s3,a2
    return -1;

  if(f->type == FD_PIPE){
80005f3c:	00052783          	lw	a5,0(a0)
80005f40:	00100713          	li	a4,1
80005f44:	06e78e63          	beq	a5,a4,80005fc0 <fileread+0xb4>
    r = piperead(f->pipe, addr, n);
  } else if(f->type == FD_DEVICE){
80005f48:	00300713          	li	a4,3
80005f4c:	08e78863          	beq	a5,a4,80005fdc <fileread+0xd0>
    if(f->major < 0 || f->major >= NDEV || !devsw[f->major].read)
      return -1;
    r = devsw[f->major].read(1, addr, n);
  } else if(f->type == FD_INODE){
80005f50:	00200713          	li	a4,2
80005f54:	0ce79663          	bne	a5,a4,80006020 <fileread+0x114>
    ilock(f->ip);
80005f58:	01052503          	lw	a0,16(a0)
80005f5c:	fffff097          	auipc	ra,0xfffff
80005f60:	95c080e7          	jalr	-1700(ra) # 800048b8 <ilock>
    if((r = readi(f->ip, 1, addr, f->off, n)) > 0)
80005f64:	00098713          	mv	a4,s3
80005f68:	0144a683          	lw	a3,20(s1)
80005f6c:	00090613          	mv	a2,s2
80005f70:	00100593          	li	a1,1
80005f74:	0104a503          	lw	a0,16(s1)
80005f78:	fffff097          	auipc	ra,0xfffff
80005f7c:	cdc080e7          	jalr	-804(ra) # 80004c54 <readi>
80005f80:	00050913          	mv	s2,a0
80005f84:	00a05863          	blez	a0,80005f94 <fileread+0x88>
      f->off += r;
80005f88:	0144a783          	lw	a5,20(s1)
80005f8c:	00a787b3          	add	a5,a5,a0
80005f90:	00f4aa23          	sw	a5,20(s1)
    iunlock(f->ip);
80005f94:	0104a503          	lw	a0,16(s1)
80005f98:	fffff097          	auipc	ra,0xfffff
80005f9c:	a2c080e7          	jalr	-1492(ra) # 800049c4 <iunlock>
80005fa0:	01412483          	lw	s1,20(sp)
80005fa4:	00c12983          	lw	s3,12(sp)
  } else {
    panic("fileread");
  }

  return r;
}
80005fa8:	00090513          	mv	a0,s2
80005fac:	01c12083          	lw	ra,28(sp)
80005fb0:	01812403          	lw	s0,24(sp)
80005fb4:	01012903          	lw	s2,16(sp)
80005fb8:	02010113          	addi	sp,sp,32
80005fbc:	00008067          	ret
    r = piperead(f->pipe, addr, n);
80005fc0:	00c52503          	lw	a0,12(a0)
80005fc4:	00000097          	auipc	ra,0x0
80005fc8:	5e4080e7          	jalr	1508(ra) # 800065a8 <piperead>
80005fcc:	00050913          	mv	s2,a0
80005fd0:	01412483          	lw	s1,20(sp)
80005fd4:	00c12983          	lw	s3,12(sp)
80005fd8:	fd1ff06f          	j	80005fa8 <fileread+0x9c>
    if(f->major < 0 || f->major >= NDEV || !devsw[f->major].read)
80005fdc:	01851783          	lh	a5,24(a0)
80005fe0:	01079693          	slli	a3,a5,0x10
80005fe4:	0106d693          	srli	a3,a3,0x10
80005fe8:	00900713          	li	a4,9
80005fec:	04d76863          	bltu	a4,a3,8000603c <fileread+0x130>
80005ff0:	00379793          	slli	a5,a5,0x3
80005ff4:	0001a717          	auipc	a4,0x1a
80005ff8:	ee870713          	addi	a4,a4,-280 # 8001fedc <devsw>
80005ffc:	00f707b3          	add	a5,a4,a5
80006000:	0007a783          	lw	a5,0(a5)
80006004:	04078663          	beqz	a5,80006050 <fileread+0x144>
    r = devsw[f->major].read(1, addr, n);
80006008:	00100513          	li	a0,1
8000600c:	000780e7          	jalr	a5
80006010:	00050913          	mv	s2,a0
80006014:	01412483          	lw	s1,20(sp)
80006018:	00c12983          	lw	s3,12(sp)
8000601c:	f8dff06f          	j	80005fa8 <fileread+0x9c>
    panic("fileread");
80006020:	00003517          	auipc	a0,0x3
80006024:	5f050513          	addi	a0,a0,1520 # 80009610 <userret+0x570>
80006028:	ffffa097          	auipc	ra,0xffffa
8000602c:	6d4080e7          	jalr	1748(ra) # 800006fc <panic>
    return -1;
80006030:	fff00793          	li	a5,-1
80006034:	00078913          	mv	s2,a5
80006038:	f71ff06f          	j	80005fa8 <fileread+0x9c>
      return -1;
8000603c:	fff00793          	li	a5,-1
80006040:	00078913          	mv	s2,a5
80006044:	01412483          	lw	s1,20(sp)
80006048:	00c12983          	lw	s3,12(sp)
8000604c:	f5dff06f          	j	80005fa8 <fileread+0x9c>
80006050:	fff00793          	li	a5,-1
80006054:	00078913          	mv	s2,a5
80006058:	01412483          	lw	s1,20(sp)
8000605c:	00c12983          	lw	s3,12(sp)
80006060:	f49ff06f          	j	80005fa8 <fileread+0x9c>

80006064 <filewrite>:
int
filewrite(struct file *f, uint32 addr, int n)
{
  int r, ret = 0;

  if(f->writable == 0)
80006064:	00954783          	lbu	a5,9(a0)
80006068:	1c078863          	beqz	a5,80006238 <filewrite+0x1d4>
{
8000606c:	fd010113          	addi	sp,sp,-48
80006070:	02112623          	sw	ra,44(sp)
80006074:	02812423          	sw	s0,40(sp)
80006078:	03212023          	sw	s2,32(sp)
8000607c:	01512a23          	sw	s5,20(sp)
80006080:	01712623          	sw	s7,12(sp)
80006084:	03010413          	addi	s0,sp,48
80006088:	00050913          	mv	s2,a0
8000608c:	00058b93          	mv	s7,a1
80006090:	00060a93          	mv	s5,a2
    return -1;

  if(f->type == FD_PIPE){
80006094:	00052783          	lw	a5,0(a0)
80006098:	00100713          	li	a4,1
8000609c:	04e78063          	beq	a5,a4,800060dc <filewrite+0x78>
    ret = pipewrite(f->pipe, addr, n);
  } else if(f->type == FD_DEVICE){
800060a0:	00300713          	li	a4,3
800060a4:	04e78463          	beq	a5,a4,800060ec <filewrite+0x88>
    if(f->major < 0 || f->major >= NDEV || !devsw[f->major].write)
      return -1;
    ret = devsw[f->major].write(1, addr, n);
  } else if(f->type == FD_INODE){
800060a8:	00200713          	li	a4,2
800060ac:	16e79463          	bne	a5,a4,80006214 <filewrite+0x1b0>
800060b0:	01312e23          	sw	s3,28(sp)
    // and 2 blocks of slop for non-aligned writes.
    // this really belongs lower down, since writei()
    // might be writing a device like the console.
    int max = ((MAXOPBLOCKS-1-1-2) / 2) * BSIZE;
    int i = 0;
    while(i < n){
800060b4:	14c05c63          	blez	a2,8000620c <filewrite+0x1a8>
800060b8:	02912223          	sw	s1,36(sp)
800060bc:	01412c23          	sw	s4,24(sp)
800060c0:	01612823          	sw	s6,16(sp)
800060c4:	01812423          	sw	s8,8(sp)
    int i = 0;
800060c8:	00000993          	li	s3,0
      int n1 = n - i;
      if(n1 > max)
800060cc:	00001b37          	lui	s6,0x1
800060d0:	c00b0b13          	addi	s6,s6,-1024 # c00 <_entry-0x7ffff400>
        n1 = max;

      begin_op();
      ilock(f->ip);
      if ((r = writei(f->ip, 1, addr + i, f->off, n1)) > 0)
800060d4:	00100c13          	li	s8,1
800060d8:	0b00006f          	j	80006188 <filewrite+0x124>
    ret = pipewrite(f->pipe, addr, n);
800060dc:	00c52503          	lw	a0,12(a0)
800060e0:	00000097          	auipc	ra,0x0
800060e4:	354080e7          	jalr	852(ra) # 80006434 <pipewrite>
800060e8:	0e40006f          	j	800061cc <filewrite+0x168>
    if(f->major < 0 || f->major >= NDEV || !devsw[f->major].write)
800060ec:	01851783          	lh	a5,24(a0)
800060f0:	01079693          	slli	a3,a5,0x10
800060f4:	0106d693          	srli	a3,a3,0x10
800060f8:	00900713          	li	a4,9
800060fc:	14d76263          	bltu	a4,a3,80006240 <filewrite+0x1dc>
80006100:	00379793          	slli	a5,a5,0x3
80006104:	0001a717          	auipc	a4,0x1a
80006108:	dd870713          	addi	a4,a4,-552 # 8001fedc <devsw>
8000610c:	00f707b3          	add	a5,a4,a5
80006110:	0047a783          	lw	a5,4(a5)
80006114:	12078a63          	beqz	a5,80006248 <filewrite+0x1e4>
    ret = devsw[f->major].write(1, addr, n);
80006118:	00100513          	li	a0,1
8000611c:	000780e7          	jalr	a5
80006120:	0ac0006f          	j	800061cc <filewrite+0x168>
      begin_op();
80006124:	fffff097          	auipc	ra,0xfffff
80006128:	554080e7          	jalr	1364(ra) # 80005678 <begin_op>
      ilock(f->ip);
8000612c:	01092503          	lw	a0,16(s2)
80006130:	ffffe097          	auipc	ra,0xffffe
80006134:	788080e7          	jalr	1928(ra) # 800048b8 <ilock>
      if ((r = writei(f->ip, 1, addr + i, f->off, n1)) > 0)
80006138:	000a0713          	mv	a4,s4
8000613c:	01492683          	lw	a3,20(s2)
80006140:	01798633          	add	a2,s3,s7
80006144:	000c0593          	mv	a1,s8
80006148:	01092503          	lw	a0,16(s2)
8000614c:	fffff097          	auipc	ra,0xfffff
80006150:	c6c080e7          	jalr	-916(ra) # 80004db8 <writei>
80006154:	00050493          	mv	s1,a0
80006158:	04a05063          	blez	a0,80006198 <filewrite+0x134>
        f->off += r;
8000615c:	01492783          	lw	a5,20(s2)
80006160:	00a787b3          	add	a5,a5,a0
80006164:	00f92a23          	sw	a5,20(s2)
      iunlock(f->ip);
80006168:	01092503          	lw	a0,16(s2)
8000616c:	fffff097          	auipc	ra,0xfffff
80006170:	858080e7          	jalr	-1960(ra) # 800049c4 <iunlock>
      end_op();
80006174:	fffff097          	auipc	ra,0xfffff
80006178:	5b8080e7          	jalr	1464(ra) # 8000572c <end_op>

      if(r < 0)
        break;
      if(r != n1)
8000617c:	069a1663          	bne	s4,s1,800061e8 <filewrite+0x184>
        panic("short filewrite");
      i += r;
80006180:	009989b3          	add	s3,s3,s1
    while(i < n){
80006184:	0759da63          	bge	s3,s5,800061f8 <filewrite+0x194>
      int n1 = n - i;
80006188:	413a8a33          	sub	s4,s5,s3
      if(n1 > max)
8000618c:	f94b5ce3          	bge	s6,s4,80006124 <filewrite+0xc0>
80006190:	000b0a13          	mv	s4,s6
80006194:	f91ff06f          	j	80006124 <filewrite+0xc0>
      iunlock(f->ip);
80006198:	01092503          	lw	a0,16(s2)
8000619c:	fffff097          	auipc	ra,0xfffff
800061a0:	828080e7          	jalr	-2008(ra) # 800049c4 <iunlock>
      end_op();
800061a4:	fffff097          	auipc	ra,0xfffff
800061a8:	588080e7          	jalr	1416(ra) # 8000572c <end_op>
      if(r < 0)
800061ac:	fc04d8e3          	bgez	s1,8000617c <filewrite+0x118>
800061b0:	02412483          	lw	s1,36(sp)
800061b4:	01812a03          	lw	s4,24(sp)
800061b8:	01012b03          	lw	s6,16(sp)
800061bc:	00812c03          	lw	s8,8(sp)
    }
    ret = (i == n ? n : -1);
800061c0:	093a9863          	bne	s5,s3,80006250 <filewrite+0x1ec>
800061c4:	000a8513          	mv	a0,s5
800061c8:	01c12983          	lw	s3,28(sp)
  } else {
    panic("filewrite");
  }

  return ret;
}
800061cc:	02c12083          	lw	ra,44(sp)
800061d0:	02812403          	lw	s0,40(sp)
800061d4:	02012903          	lw	s2,32(sp)
800061d8:	01412a83          	lw	s5,20(sp)
800061dc:	00c12b83          	lw	s7,12(sp)
800061e0:	03010113          	addi	sp,sp,48
800061e4:	00008067          	ret
        panic("short filewrite");
800061e8:	00003517          	auipc	a0,0x3
800061ec:	43450513          	addi	a0,a0,1076 # 8000961c <userret+0x57c>
800061f0:	ffffa097          	auipc	ra,0xffffa
800061f4:	50c080e7          	jalr	1292(ra) # 800006fc <panic>
800061f8:	02412483          	lw	s1,36(sp)
800061fc:	01812a03          	lw	s4,24(sp)
80006200:	01012b03          	lw	s6,16(sp)
80006204:	00812c03          	lw	s8,8(sp)
80006208:	fb9ff06f          	j	800061c0 <filewrite+0x15c>
    int i = 0;
8000620c:	00000993          	li	s3,0
80006210:	fb1ff06f          	j	800061c0 <filewrite+0x15c>
80006214:	02912223          	sw	s1,36(sp)
80006218:	01312e23          	sw	s3,28(sp)
8000621c:	01412c23          	sw	s4,24(sp)
80006220:	01612823          	sw	s6,16(sp)
80006224:	01812423          	sw	s8,8(sp)
    panic("filewrite");
80006228:	00003517          	auipc	a0,0x3
8000622c:	40450513          	addi	a0,a0,1028 # 8000962c <userret+0x58c>
80006230:	ffffa097          	auipc	ra,0xffffa
80006234:	4cc080e7          	jalr	1228(ra) # 800006fc <panic>
    return -1;
80006238:	fff00513          	li	a0,-1
}
8000623c:	00008067          	ret
      return -1;
80006240:	fff00513          	li	a0,-1
80006244:	f89ff06f          	j	800061cc <filewrite+0x168>
80006248:	fff00513          	li	a0,-1
8000624c:	f81ff06f          	j	800061cc <filewrite+0x168>
    ret = (i == n ? n : -1);
80006250:	fff00513          	li	a0,-1
80006254:	01c12983          	lw	s3,28(sp)
80006258:	f75ff06f          	j	800061cc <filewrite+0x168>

8000625c <pipealloc>:
  int writeopen;  // write fd is still open
};

int
pipealloc(struct file **f0, struct file **f1)
{
8000625c:	fe010113          	addi	sp,sp,-32
80006260:	00112e23          	sw	ra,28(sp)
80006264:	00812c23          	sw	s0,24(sp)
80006268:	00912a23          	sw	s1,20(sp)
8000626c:	01412423          	sw	s4,8(sp)
80006270:	02010413          	addi	s0,sp,32
80006274:	00050493          	mv	s1,a0
80006278:	00058a13          	mv	s4,a1
  struct pipe *pi;

  pi = 0;
  *f0 = *f1 = 0;
8000627c:	0005a023          	sw	zero,0(a1)
80006280:	00052023          	sw	zero,0(a0)
  if((*f0 = filealloc()) == 0 || (*f1 = filealloc()) == 0)
80006284:	00000097          	auipc	ra,0x0
80006288:	994080e7          	jalr	-1644(ra) # 80005c18 <filealloc>
8000628c:	00a4a023          	sw	a0,0(s1)
80006290:	0c050463          	beqz	a0,80006358 <pipealloc+0xfc>
80006294:	00000097          	auipc	ra,0x0
80006298:	984080e7          	jalr	-1660(ra) # 80005c18 <filealloc>
8000629c:	00aa2023          	sw	a0,0(s4)
800062a0:	0a050463          	beqz	a0,80006348 <pipealloc+0xec>
800062a4:	01212823          	sw	s2,16(sp)
    goto bad;
  if((pi = (struct pipe*)kalloc()) == 0)
800062a8:	ffffb097          	auipc	ra,0xffffb
800062ac:	a38080e7          	jalr	-1480(ra) # 80000ce0 <kalloc>
800062b0:	00050913          	mv	s2,a0
800062b4:	06050e63          	beqz	a0,80006330 <pipealloc+0xd4>
800062b8:	01312623          	sw	s3,12(sp)
    goto bad;
  pi->readopen = 1;
800062bc:	00100993          	li	s3,1
800062c0:	21352a23          	sw	s3,532(a0)
  pi->writeopen = 1;
800062c4:	21352c23          	sw	s3,536(a0)
  pi->nwrite = 0;
800062c8:	20052823          	sw	zero,528(a0)
  pi->nread = 0;
800062cc:	20052623          	sw	zero,524(a0)
  initlock(&pi->lock, "pipe");
800062d0:	00003597          	auipc	a1,0x3
800062d4:	36858593          	addi	a1,a1,872 # 80009638 <userret+0x598>
800062d8:	ffffb097          	auipc	ra,0xffffb
800062dc:	a94080e7          	jalr	-1388(ra) # 80000d6c <initlock>
  (*f0)->type = FD_PIPE;
800062e0:	0004a783          	lw	a5,0(s1)
800062e4:	0137a023          	sw	s3,0(a5)
  (*f0)->readable = 1;
800062e8:	0004a783          	lw	a5,0(s1)
800062ec:	01378423          	sb	s3,8(a5)
  (*f0)->writable = 0;
800062f0:	0004a783          	lw	a5,0(s1)
800062f4:	000784a3          	sb	zero,9(a5)
  (*f0)->pipe = pi;
800062f8:	0004a783          	lw	a5,0(s1)
800062fc:	0127a623          	sw	s2,12(a5)
  (*f1)->type = FD_PIPE;
80006300:	000a2783          	lw	a5,0(s4)
80006304:	0137a023          	sw	s3,0(a5)
  (*f1)->readable = 0;
80006308:	000a2783          	lw	a5,0(s4)
8000630c:	00078423          	sb	zero,8(a5)
  (*f1)->writable = 1;
80006310:	000a2783          	lw	a5,0(s4)
80006314:	013784a3          	sb	s3,9(a5)
  (*f1)->pipe = pi;
80006318:	000a2783          	lw	a5,0(s4)
8000631c:	0127a623          	sw	s2,12(a5)
  return 0;
80006320:	00000513          	li	a0,0
80006324:	01012903          	lw	s2,16(sp)
80006328:	00c12983          	lw	s3,12(sp)
8000632c:	0480006f          	j	80006374 <pipealloc+0x118>

 bad:
  if(pi)
    kfree((char*)pi);
  if(*f0)
80006330:	0004a503          	lw	a0,0(s1)
80006334:	00050663          	beqz	a0,80006340 <pipealloc+0xe4>
80006338:	01012903          	lw	s2,16(sp)
8000633c:	0140006f          	j	80006350 <pipealloc+0xf4>
80006340:	01012903          	lw	s2,16(sp)
80006344:	0140006f          	j	80006358 <pipealloc+0xfc>
80006348:	0004a503          	lw	a0,0(s1)
8000634c:	04050063          	beqz	a0,8000638c <pipealloc+0x130>
    fileclose(*f0);
80006350:	00000097          	auipc	ra,0x0
80006354:	9c4080e7          	jalr	-1596(ra) # 80005d14 <fileclose>
  if(*f1)
80006358:	000a2783          	lw	a5,0(s4)
    fileclose(*f1);
  return -1;
8000635c:	fff00513          	li	a0,-1
  if(*f1)
80006360:	00078a63          	beqz	a5,80006374 <pipealloc+0x118>
    fileclose(*f1);
80006364:	00078513          	mv	a0,a5
80006368:	00000097          	auipc	ra,0x0
8000636c:	9ac080e7          	jalr	-1620(ra) # 80005d14 <fileclose>
  return -1;
80006370:	fff00513          	li	a0,-1
}
80006374:	01c12083          	lw	ra,28(sp)
80006378:	01812403          	lw	s0,24(sp)
8000637c:	01412483          	lw	s1,20(sp)
80006380:	00812a03          	lw	s4,8(sp)
80006384:	02010113          	addi	sp,sp,32
80006388:	00008067          	ret
  return -1;
8000638c:	fff00513          	li	a0,-1
80006390:	fe5ff06f          	j	80006374 <pipealloc+0x118>

80006394 <pipeclose>:

void
pipeclose(struct pipe *pi, int writable)
{
80006394:	ff010113          	addi	sp,sp,-16
80006398:	00112623          	sw	ra,12(sp)
8000639c:	00812423          	sw	s0,8(sp)
800063a0:	00912223          	sw	s1,4(sp)
800063a4:	01212023          	sw	s2,0(sp)
800063a8:	01010413          	addi	s0,sp,16
800063ac:	00050493          	mv	s1,a0
800063b0:	00058913          	mv	s2,a1
  acquire(&pi->lock);
800063b4:	ffffb097          	auipc	ra,0xffffb
800063b8:	b48080e7          	jalr	-1208(ra) # 80000efc <acquire>
  if(writable){
800063bc:	04090463          	beqz	s2,80006404 <pipeclose+0x70>
    pi->writeopen = 0;
800063c0:	2004ac23          	sw	zero,536(s1)
    wakeup(&pi->nread);
800063c4:	20c48513          	addi	a0,s1,524
800063c8:	ffffd097          	auipc	ra,0xffffd
800063cc:	b64080e7          	jalr	-1180(ra) # 80002f2c <wakeup>
  } else {
    pi->readopen = 0;
    wakeup(&pi->nwrite);
  }
  if(pi->readopen == 0 && pi->writeopen == 0){
800063d0:	2144a783          	lw	a5,532(s1)
800063d4:	00079663          	bnez	a5,800063e0 <pipeclose+0x4c>
800063d8:	2184a783          	lw	a5,536(s1)
800063dc:	02078e63          	beqz	a5,80006418 <pipeclose+0x84>
    release(&pi->lock);
    kfree((char*)pi);
  } else
    release(&pi->lock);
800063e0:	00048513          	mv	a0,s1
800063e4:	ffffb097          	auipc	ra,0xffffb
800063e8:	b8c080e7          	jalr	-1140(ra) # 80000f70 <release>
}
800063ec:	00c12083          	lw	ra,12(sp)
800063f0:	00812403          	lw	s0,8(sp)
800063f4:	00412483          	lw	s1,4(sp)
800063f8:	00012903          	lw	s2,0(sp)
800063fc:	01010113          	addi	sp,sp,16
80006400:	00008067          	ret
    pi->readopen = 0;
80006404:	2004aa23          	sw	zero,532(s1)
    wakeup(&pi->nwrite);
80006408:	21048513          	addi	a0,s1,528
8000640c:	ffffd097          	auipc	ra,0xffffd
80006410:	b20080e7          	jalr	-1248(ra) # 80002f2c <wakeup>
80006414:	fbdff06f          	j	800063d0 <pipeclose+0x3c>
    release(&pi->lock);
80006418:	00048513          	mv	a0,s1
8000641c:	ffffb097          	auipc	ra,0xffffb
80006420:	b54080e7          	jalr	-1196(ra) # 80000f70 <release>
    kfree((char*)pi);
80006424:	00048513          	mv	a0,s1
80006428:	ffffa097          	auipc	ra,0xffffa
8000642c:	748080e7          	jalr	1864(ra) # 80000b70 <kfree>
80006430:	fbdff06f          	j	800063ec <pipeclose+0x58>

80006434 <pipewrite>:

int
pipewrite(struct pipe *pi, uint32 addr, int n)
{
80006434:	fc010113          	addi	sp,sp,-64
80006438:	02112e23          	sw	ra,60(sp)
8000643c:	02812c23          	sw	s0,56(sp)
80006440:	02912a23          	sw	s1,52(sp)
80006444:	03412423          	sw	s4,40(sp)
80006448:	03512223          	sw	s5,36(sp)
8000644c:	03612023          	sw	s6,32(sp)
80006450:	04010413          	addi	s0,sp,64
80006454:	00050493          	mv	s1,a0
80006458:	00058a93          	mv	s5,a1
8000645c:	00060a13          	mv	s4,a2
  int i;
  char ch;
  struct proc *pr = myproc();
80006460:	ffffc097          	auipc	ra,0xffffc
80006464:	e7c080e7          	jalr	-388(ra) # 800022dc <myproc>
80006468:	00050b13          	mv	s6,a0

  acquire(&pi->lock);
8000646c:	00048513          	mv	a0,s1
80006470:	ffffb097          	auipc	ra,0xffffb
80006474:	a8c080e7          	jalr	-1396(ra) # 80000efc <acquire>
  for(i = 0; i < n; i++){
80006478:	11405863          	blez	s4,80006588 <pipewrite+0x154>
8000647c:	03212823          	sw	s2,48(sp)
80006480:	03312623          	sw	s3,44(sp)
80006484:	01712e23          	sw	s7,28(sp)
80006488:	015a07b3          	add	a5,s4,s5
8000648c:	00078b93          	mv	s7,a5
    while(pi->nwrite == pi->nread + PIPESIZE){  //DOC: pipewrite-full
      if(pi->readopen == 0 || myproc()->killed){
        release(&pi->lock);
        return -1;
      }
      wakeup(&pi->nread);
80006490:	20c48993          	addi	s3,s1,524
      sleep(&pi->nwrite, &pi->lock);
80006494:	21048913          	addi	s2,s1,528
    while(pi->nwrite == pi->nread + PIPESIZE){  //DOC: pipewrite-full
80006498:	20c4a783          	lw	a5,524(s1)
8000649c:	20078793          	addi	a5,a5,512
800064a0:	2104a703          	lw	a4,528(s1)
800064a4:	04f71463          	bne	a4,a5,800064ec <pipewrite+0xb8>
      if(pi->readopen == 0 || myproc()->killed){
800064a8:	2144a783          	lw	a5,532(s1)
800064ac:	08078a63          	beqz	a5,80006540 <pipewrite+0x10c>
800064b0:	ffffc097          	auipc	ra,0xffffc
800064b4:	e2c080e7          	jalr	-468(ra) # 800022dc <myproc>
800064b8:	01852783          	lw	a5,24(a0)
800064bc:	08079263          	bnez	a5,80006540 <pipewrite+0x10c>
      wakeup(&pi->nread);
800064c0:	00098513          	mv	a0,s3
800064c4:	ffffd097          	auipc	ra,0xffffd
800064c8:	a68080e7          	jalr	-1432(ra) # 80002f2c <wakeup>
      sleep(&pi->nwrite, &pi->lock);
800064cc:	00048593          	mv	a1,s1
800064d0:	00090513          	mv	a0,s2
800064d4:	ffffd097          	auipc	ra,0xffffd
800064d8:	848080e7          	jalr	-1976(ra) # 80002d1c <sleep>
    while(pi->nwrite == pi->nread + PIPESIZE){  //DOC: pipewrite-full
800064dc:	20c4a783          	lw	a5,524(s1)
800064e0:	20078793          	addi	a5,a5,512
800064e4:	2104a703          	lw	a4,528(s1)
800064e8:	fcf700e3          	beq	a4,a5,800064a8 <pipewrite+0x74>
    }
    if(copyin(pr->pagetable, &ch, addr + i, 1) == -1)
800064ec:	00100693          	li	a3,1
800064f0:	000a8613          	mv	a2,s5
800064f4:	fcf40593          	addi	a1,s0,-49
800064f8:	02cb2503          	lw	a0,44(s6)
800064fc:	ffffc097          	auipc	ra,0xffffc
80006500:	9e8080e7          	jalr	-1560(ra) # 80001ee4 <copyin>
80006504:	fff00793          	li	a5,-1
80006508:	06f50a63          	beq	a0,a5,8000657c <pipewrite+0x148>
      break;
    pi->data[pi->nwrite++ % PIPESIZE] = ch;
8000650c:	2104a783          	lw	a5,528(s1)
80006510:	00178713          	addi	a4,a5,1
80006514:	20e4a823          	sw	a4,528(s1)
80006518:	1ff7f793          	andi	a5,a5,511
8000651c:	00f487b3          	add	a5,s1,a5
80006520:	fcf44703          	lbu	a4,-49(s0)
80006524:	00e78623          	sb	a4,12(a5)
  for(i = 0; i < n; i++){
80006528:	001a8a93          	addi	s5,s5,1
8000652c:	f77a96e3          	bne	s5,s7,80006498 <pipewrite+0x64>
80006530:	03012903          	lw	s2,48(sp)
80006534:	02c12983          	lw	s3,44(sp)
80006538:	01c12b83          	lw	s7,28(sp)
8000653c:	04c0006f          	j	80006588 <pipewrite+0x154>
        release(&pi->lock);
80006540:	00048513          	mv	a0,s1
80006544:	ffffb097          	auipc	ra,0xffffb
80006548:	a2c080e7          	jalr	-1492(ra) # 80000f70 <release>
        return -1;
8000654c:	fff00513          	li	a0,-1
80006550:	03012903          	lw	s2,48(sp)
80006554:	02c12983          	lw	s3,44(sp)
80006558:	01c12b83          	lw	s7,28(sp)
  }
  wakeup(&pi->nread);
  release(&pi->lock);
  return n;
}
8000655c:	03c12083          	lw	ra,60(sp)
80006560:	03812403          	lw	s0,56(sp)
80006564:	03412483          	lw	s1,52(sp)
80006568:	02812a03          	lw	s4,40(sp)
8000656c:	02412a83          	lw	s5,36(sp)
80006570:	02012b03          	lw	s6,32(sp)
80006574:	04010113          	addi	sp,sp,64
80006578:	00008067          	ret
8000657c:	03012903          	lw	s2,48(sp)
80006580:	02c12983          	lw	s3,44(sp)
80006584:	01c12b83          	lw	s7,28(sp)
  wakeup(&pi->nread);
80006588:	20c48513          	addi	a0,s1,524
8000658c:	ffffd097          	auipc	ra,0xffffd
80006590:	9a0080e7          	jalr	-1632(ra) # 80002f2c <wakeup>
  release(&pi->lock);
80006594:	00048513          	mv	a0,s1
80006598:	ffffb097          	auipc	ra,0xffffb
8000659c:	9d8080e7          	jalr	-1576(ra) # 80000f70 <release>
  return n;
800065a0:	000a0513          	mv	a0,s4
800065a4:	fb9ff06f          	j	8000655c <pipewrite+0x128>

800065a8 <piperead>:

int
piperead(struct pipe *pi, uint32 addr, int n)
{
800065a8:	fc010113          	addi	sp,sp,-64
800065ac:	02112e23          	sw	ra,60(sp)
800065b0:	02812c23          	sw	s0,56(sp)
800065b4:	02912a23          	sw	s1,52(sp)
800065b8:	03212823          	sw	s2,48(sp)
800065bc:	03312623          	sw	s3,44(sp)
800065c0:	03412423          	sw	s4,40(sp)
800065c4:	03512223          	sw	s5,36(sp)
800065c8:	04010413          	addi	s0,sp,64
800065cc:	00050493          	mv	s1,a0
800065d0:	00058a93          	mv	s5,a1
800065d4:	00060993          	mv	s3,a2
  int i;
  struct proc *pr = myproc();
800065d8:	ffffc097          	auipc	ra,0xffffc
800065dc:	d04080e7          	jalr	-764(ra) # 800022dc <myproc>
800065e0:	00050a13          	mv	s4,a0
  char ch;

  acquire(&pi->lock);
800065e4:	00048513          	mv	a0,s1
800065e8:	ffffb097          	auipc	ra,0xffffb
800065ec:	914080e7          	jalr	-1772(ra) # 80000efc <acquire>
  while(pi->nread == pi->nwrite && pi->writeopen){  //DOC: pipe-empty
800065f0:	20c4a703          	lw	a4,524(s1)
800065f4:	2104a783          	lw	a5,528(s1)
    if(myproc()->killed){
      release(&pi->lock);
      return -1;
    }
    sleep(&pi->nread, &pi->lock); //DOC: piperead-sleep
800065f8:	20c48913          	addi	s2,s1,524
  while(pi->nread == pi->nwrite && pi->writeopen){  //DOC: pipe-empty
800065fc:	04f71463          	bne	a4,a5,80006644 <piperead+0x9c>
80006600:	2184a783          	lw	a5,536(s1)
80006604:	06078263          	beqz	a5,80006668 <piperead+0xc0>
    if(myproc()->killed){
80006608:	ffffc097          	auipc	ra,0xffffc
8000660c:	cd4080e7          	jalr	-812(ra) # 800022dc <myproc>
80006610:	01852783          	lw	a5,24(a0)
80006614:	04079063          	bnez	a5,80006654 <piperead+0xac>
    sleep(&pi->nread, &pi->lock); //DOC: piperead-sleep
80006618:	00048593          	mv	a1,s1
8000661c:	00090513          	mv	a0,s2
80006620:	ffffc097          	auipc	ra,0xffffc
80006624:	6fc080e7          	jalr	1788(ra) # 80002d1c <sleep>
  while(pi->nread == pi->nwrite && pi->writeopen){  //DOC: pipe-empty
80006628:	20c4a703          	lw	a4,524(s1)
8000662c:	2104a783          	lw	a5,528(s1)
80006630:	fcf708e3          	beq	a4,a5,80006600 <piperead+0x58>
80006634:	03612023          	sw	s6,32(sp)
80006638:	01712e23          	sw	s7,28(sp)
8000663c:	01812c23          	sw	s8,24(sp)
80006640:	0340006f          	j	80006674 <piperead+0xcc>
80006644:	03612023          	sw	s6,32(sp)
80006648:	01712e23          	sw	s7,28(sp)
8000664c:	01812c23          	sw	s8,24(sp)
80006650:	0240006f          	j	80006674 <piperead+0xcc>
      release(&pi->lock);
80006654:	00048513          	mv	a0,s1
80006658:	ffffb097          	auipc	ra,0xffffb
8000665c:	918080e7          	jalr	-1768(ra) # 80000f70 <release>
      return -1;
80006660:	fff00913          	li	s2,-1
80006664:	0900006f          	j	800066f4 <piperead+0x14c>
80006668:	03612023          	sw	s6,32(sp)
8000666c:	01712e23          	sw	s7,28(sp)
80006670:	01812c23          	sw	s8,24(sp)
  }
  for(i = 0; i < n; i++){  //DOC: piperead-copy
80006674:	00000913          	li	s2,0
    if(pi->nread == pi->nwrite)
      break;
    ch = pi->data[pi->nread++ % PIPESIZE];
    if(copyout(pr->pagetable, addr + i, &ch, 1) == -1)
80006678:	fcf40c13          	addi	s8,s0,-49
8000667c:	00100b93          	li	s7,1
80006680:	fff00b13          	li	s6,-1
  for(i = 0; i < n; i++){  //DOC: piperead-copy
80006684:	05305663          	blez	s3,800066d0 <piperead+0x128>
    if(pi->nread == pi->nwrite)
80006688:	20c4a783          	lw	a5,524(s1)
8000668c:	2104a703          	lw	a4,528(s1)
80006690:	04e78063          	beq	a5,a4,800066d0 <piperead+0x128>
    ch = pi->data[pi->nread++ % PIPESIZE];
80006694:	00178713          	addi	a4,a5,1
80006698:	20e4a623          	sw	a4,524(s1)
8000669c:	1ff7f793          	andi	a5,a5,511
800066a0:	00f487b3          	add	a5,s1,a5
800066a4:	00c7c783          	lbu	a5,12(a5)
800066a8:	fcf407a3          	sb	a5,-49(s0)
    if(copyout(pr->pagetable, addr + i, &ch, 1) == -1)
800066ac:	000b8693          	mv	a3,s7
800066b0:	000c0613          	mv	a2,s8
800066b4:	015905b3          	add	a1,s2,s5
800066b8:	02ca2503          	lw	a0,44(s4)
800066bc:	ffffb097          	auipc	ra,0xffffb
800066c0:	740080e7          	jalr	1856(ra) # 80001dfc <copyout>
800066c4:	01650663          	beq	a0,s6,800066d0 <piperead+0x128>
  for(i = 0; i < n; i++){  //DOC: piperead-copy
800066c8:	00190913          	addi	s2,s2,1
800066cc:	fb299ee3          	bne	s3,s2,80006688 <piperead+0xe0>
      break;
  }
  wakeup(&pi->nwrite);  //DOC: piperead-wakeup
800066d0:	21048513          	addi	a0,s1,528
800066d4:	ffffd097          	auipc	ra,0xffffd
800066d8:	858080e7          	jalr	-1960(ra) # 80002f2c <wakeup>
  release(&pi->lock);
800066dc:	00048513          	mv	a0,s1
800066e0:	ffffb097          	auipc	ra,0xffffb
800066e4:	890080e7          	jalr	-1904(ra) # 80000f70 <release>
800066e8:	02012b03          	lw	s6,32(sp)
800066ec:	01c12b83          	lw	s7,28(sp)
800066f0:	01812c03          	lw	s8,24(sp)
  return i;
}
800066f4:	00090513          	mv	a0,s2
800066f8:	03c12083          	lw	ra,60(sp)
800066fc:	03812403          	lw	s0,56(sp)
80006700:	03412483          	lw	s1,52(sp)
80006704:	03012903          	lw	s2,48(sp)
80006708:	02c12983          	lw	s3,44(sp)
8000670c:	02812a03          	lw	s4,40(sp)
80006710:	02412a83          	lw	s5,36(sp)
80006714:	04010113          	addi	sp,sp,64
80006718:	00008067          	ret

8000671c <exec>:

static int loadseg(pde_t *pgdir, uint32 addr, struct inode *ip, uint offset, uint sz);

int
exec(char *path, char **argv)
{
8000671c:	ed010113          	addi	sp,sp,-304
80006720:	12112623          	sw	ra,300(sp)
80006724:	12812423          	sw	s0,296(sp)
80006728:	12912223          	sw	s1,292(sp)
8000672c:	13212023          	sw	s2,288(sp)
80006730:	13010413          	addi	s0,sp,304
80006734:	00050913          	mv	s2,a0
80006738:	eca42c23          	sw	a0,-296(s0)
8000673c:	ecb42a23          	sw	a1,-300(s0)
  int fail_step = 0;
  struct elfhdr elf;
  struct inode *ip;
  struct proghdr ph;
  pagetable_t pagetable = 0, oldpagetable;
  struct proc *p = myproc();
80006740:	ffffc097          	auipc	ra,0xffffc
80006744:	b9c080e7          	jalr	-1124(ra) # 800022dc <myproc>
80006748:	00050493          	mv	s1,a0

  begin_op();
8000674c:	fffff097          	auipc	ra,0xfffff
80006750:	f2c080e7          	jalr	-212(ra) # 80005678 <begin_op>

  if((ip = namei(path)) == 0){
80006754:	00090513          	mv	a0,s2
80006758:	fffff097          	auipc	ra,0xfffff
8000675c:	c5c080e7          	jalr	-932(ra) # 800053b4 <namei>
80006760:	0a050463          	beqz	a0,80006808 <exec+0xec>
80006764:	11512a23          	sw	s5,276(sp)
80006768:	00050a93          	mv	s5,a0
    fail_step = 1;
    end_op();
    return -1;
  }
  ilock(ip);
8000676c:	ffffe097          	auipc	ra,0xffffe
80006770:	14c080e7          	jalr	332(ra) # 800048b8 <ilock>

  // Check ELF header
  if(readi(ip, 0, (uint32)&elf, 0, sizeof(elf)) != sizeof(elf)) {
80006774:	03400713          	li	a4,52
80006778:	00000693          	li	a3,0
8000677c:	f0840613          	addi	a2,s0,-248
80006780:	00000593          	li	a1,0
80006784:	000a8513          	mv	a0,s5
80006788:	ffffe097          	auipc	ra,0xffffe
8000678c:	4cc080e7          	jalr	1228(ra) # 80004c54 <readi>
80006790:	03400793          	li	a5,52
80006794:	4af51663          	bne	a0,a5,80006c40 <exec+0x524>
    fail_step = 2;
    goto bad;
  }
  if(elf.magic != ELF_MAGIC) {
80006798:	f0842703          	lw	a4,-248(s0)
8000679c:	464c47b7          	lui	a5,0x464c4
800067a0:	57f78793          	addi	a5,a5,1407 # 464c457f <_entry-0x39b3ba81>
    fail_step = 3;
800067a4:	00300593          	li	a1,3
  if(elf.magic != ELF_MAGIC) {
800067a8:	48f71e63          	bne	a4,a5,80006c44 <exec+0x528>
800067ac:	11612823          	sw	s6,272(sp)
    goto bad;
  }

  if((pagetable = proc_pagetable(p)) == 0) {
800067b0:	00048513          	mv	a0,s1
800067b4:	ffffc097          	auipc	ra,0xffffc
800067b8:	c44080e7          	jalr	-956(ra) # 800023f8 <proc_pagetable>
800067bc:	00050b13          	mv	s6,a0
800067c0:	4c050663          	beqz	a0,80006c8c <exec+0x570>
800067c4:	11312e23          	sw	s3,284(sp)
800067c8:	11412c23          	sw	s4,280(sp)
800067cc:	11712623          	sw	s7,268(sp)
800067d0:	11812423          	sw	s8,264(sp)
800067d4:	11912223          	sw	s9,260(sp)
    goto bad;
  }

  // Load program into memory.
  sz = 0;
  for(i=0, off=elf.phoff; i<elf.phnum; i++, off+=sizeof(ph)){
800067d8:	f3445783          	lhu	a5,-204(s0)
800067dc:	1e078063          	beqz	a5,800069bc <exec+0x2a0>
800067e0:	11a12023          	sw	s10,256(sp)
800067e4:	0fb12e23          	sw	s11,252(sp)
800067e8:	f2442903          	lw	s2,-220(s0)
  sz = 0;
800067ec:	ec042e23          	sw	zero,-292(s0)
  for(i=0, off=elf.phoff; i<elf.phnum; i++, off+=sizeof(ph)){
800067f0:	00000c93          	li	s9,0



    if(readi(ip, 0, (uint32)&ph, off, sizeof(ph)) != sizeof(ph)) {
800067f4:	02000d13          	li	s10,32
    }
    if((sz = uvmalloc(pagetable, sz, ph.vaddr + ph.memsz)) == 0) {
      fail_step = 8;
      goto bad;
    }
    if(ph.vaddr % PGSIZE != 0) {
800067f8:	000019b7          	lui	s3,0x1
800067fc:	fff98793          	addi	a5,s3,-1 # fff <_entry-0x7ffff001>
80006800:	ecf42823          	sw	a5,-304(s0)
80006804:	0b80006f          	j	800068bc <exec+0x1a0>
    end_op();
80006808:	fffff097          	auipc	ra,0xfffff
8000680c:	f24080e7          	jalr	-220(ra) # 8000572c <end_op>
    return -1;
80006810:	fff00513          	li	a0,-1
80006814:	4600006f          	j	80006c74 <exec+0x558>
      fail_step = 9;
      printf("exec ph misalign path=%s off=%d vaddr=0x%x filesz=0x%x memsz=0x%x type=0x%x\n",
80006818:	ee842803          	lw	a6,-280(s0)
8000681c:	efc42783          	lw	a5,-260(s0)
80006820:	ef842703          	lw	a4,-264(s0)
80006824:	000b8693          	mv	a3,s7
80006828:	00090613          	mv	a2,s2
8000682c:	ed842583          	lw	a1,-296(s0)
80006830:	00003517          	auipc	a0,0x3
80006834:	e1050513          	addi	a0,a0,-496 # 80009640 <userret+0x5a0>
80006838:	ffffa097          	auipc	ra,0xffffa
8000683c:	f20080e7          	jalr	-224(ra) # 80000758 <printf>
      fail_step = 9;
80006840:	00900593          	li	a1,9
             path, off, ph.vaddr, ph.filesz, ph.memsz, ph.type);
      goto bad;
80006844:	10012d03          	lw	s10,256(sp)
80006848:	0fc12d83          	lw	s11,252(sp)
8000684c:	1580006f          	j	800069a4 <exec+0x288>
    panic("loadseg: va must be page aligned");

  for(i = 0; i < sz; i += PGSIZE){
    pa = walkaddr(pagetable, va + i);
    if(pa == 0)
      panic("loadseg: address should exist");
80006850:	00003517          	auipc	a0,0x3
80006854:	e4050513          	addi	a0,a0,-448 # 80009690 <userret+0x5f0>
80006858:	ffffa097          	auipc	ra,0xffffa
8000685c:	ea4080e7          	jalr	-348(ra) # 800006fc <panic>
    if(sz - i < PGSIZE)
      n = sz - i;
    else
      n = PGSIZE;
    if(readi(ip, 0, (uint32)pa, offset+i, n) != n)
80006860:	00090713          	mv	a4,s2
80006864:	009c06b3          	add	a3,s8,s1
80006868:	00000593          	li	a1,0
8000686c:	000a8513          	mv	a0,s5
80006870:	ffffe097          	auipc	ra,0xffffe
80006874:	3e4080e7          	jalr	996(ra) # 80004c54 <readi>
80006878:	32a91863          	bne	s2,a0,80006ba8 <exec+0x48c>
  for(i = 0; i < sz; i += PGSIZE){
8000687c:	013484b3          	add	s1,s1,s3
80006880:	0344f663          	bgeu	s1,s4,800068ac <exec+0x190>
    pa = walkaddr(pagetable, va + i);
80006884:	009b85b3          	add	a1,s7,s1
80006888:	000b0513          	mv	a0,s6
8000688c:	ffffb097          	auipc	ra,0xffffb
80006890:	c88080e7          	jalr	-888(ra) # 80001514 <walkaddr>
80006894:	00050613          	mv	a2,a0
    if(pa == 0)
80006898:	fa050ce3          	beqz	a0,80006850 <exec+0x134>
    if(sz - i < PGSIZE)
8000689c:	409a0933          	sub	s2,s4,s1
800068a0:	fd29f0e3          	bgeu	s3,s2,80006860 <exec+0x144>
800068a4:	00098913          	mv	s2,s3
800068a8:	fb9ff06f          	j	80006860 <exec+0x144>
  for(i=0, off=elf.phoff; i<elf.phnum; i++, off+=sizeof(ph)){
800068ac:	001c8c93          	addi	s9,s9,1
800068b0:	020d8913          	addi	s2,s11,32
800068b4:	f3445783          	lhu	a5,-204(s0)
800068b8:	08fcd263          	bge	s9,a5,8000693c <exec+0x220>
    if(readi(ip, 0, (uint32)&ph, off, sizeof(ph)) != sizeof(ph)) {
800068bc:	00090d93          	mv	s11,s2
800068c0:	000d0713          	mv	a4,s10
800068c4:	00090693          	mv	a3,s2
800068c8:	ee840613          	addi	a2,s0,-280
800068cc:	00000593          	li	a1,0
800068d0:	000a8513          	mv	a0,s5
800068d4:	ffffe097          	auipc	ra,0xffffe
800068d8:	380080e7          	jalr	896(ra) # 80004c54 <readi>
800068dc:	29a51663          	bne	a0,s10,80006b68 <exec+0x44c>
    if(ph.type != ELF_PROG_LOAD)
800068e0:	ee842783          	lw	a5,-280(s0)
800068e4:	00100713          	li	a4,1
800068e8:	fce792e3          	bne	a5,a4,800068ac <exec+0x190>
    if(ph.memsz < ph.filesz) {
800068ec:	efc42603          	lw	a2,-260(s0)
800068f0:	ef842783          	lw	a5,-264(s0)
800068f4:	28f66263          	bltu	a2,a5,80006b78 <exec+0x45c>
    if(ph.vaddr + ph.memsz < ph.vaddr) {
800068f8:	ef042783          	lw	a5,-272(s0)
800068fc:	00f60633          	add	a2,a2,a5
80006900:	28f66463          	bltu	a2,a5,80006b88 <exec+0x46c>
    if((sz = uvmalloc(pagetable, sz, ph.vaddr + ph.memsz)) == 0) {
80006904:	edc42583          	lw	a1,-292(s0)
80006908:	000b0513          	mv	a0,s6
8000690c:	ffffb097          	auipc	ra,0xffffb
80006910:	1d8080e7          	jalr	472(ra) # 80001ae4 <uvmalloc>
80006914:	eca42e23          	sw	a0,-292(s0)
80006918:	28050063          	beqz	a0,80006b98 <exec+0x47c>
    if(ph.vaddr % PGSIZE != 0) {
8000691c:	ef042b83          	lw	s7,-272(s0)
80006920:	ed042783          	lw	a5,-304(s0)
80006924:	00fbf4b3          	and	s1,s7,a5
80006928:	ee0498e3          	bnez	s1,80006818 <exec+0xfc>
    if(loadseg(pagetable, ph.vaddr, ip, ph.off, ph.filesz) < 0) {
8000692c:	ef842a03          	lw	s4,-264(s0)
  for(i = 0; i < sz; i += PGSIZE){
80006930:	f60a0ee3          	beqz	s4,800068ac <exec+0x190>
    if(loadseg(pagetable, ph.vaddr, ip, ph.off, ph.filesz) < 0) {
80006934:	eec42c03          	lw	s8,-276(s0)
80006938:	f4dff06f          	j	80006884 <exec+0x168>
8000693c:	10012d03          	lw	s10,256(sp)
80006940:	0fc12d83          	lw	s11,252(sp)
  iunlockput(ip);
80006944:	000a8513          	mv	a0,s5
80006948:	ffffe097          	auipc	ra,0xffffe
8000694c:	280080e7          	jalr	640(ra) # 80004bc8 <iunlockput>
  end_op();
80006950:	fffff097          	auipc	ra,0xfffff
80006954:	ddc080e7          	jalr	-548(ra) # 8000572c <end_op>
  p = myproc();
80006958:	ffffc097          	auipc	ra,0xffffc
8000695c:	984080e7          	jalr	-1660(ra) # 800022dc <myproc>
80006960:	00050a13          	mv	s4,a0
  uint32 oldsz = p->sz;
80006964:	02852c83          	lw	s9,40(a0)
  sz = PGROUNDUP(sz);
80006968:	000015b7          	lui	a1,0x1
8000696c:	fff58593          	addi	a1,a1,-1 # fff <_entry-0x7ffff001>
80006970:	edc42783          	lw	a5,-292(s0)
80006974:	00b785b3          	add	a1,a5,a1
80006978:	fffff7b7          	lui	a5,0xfffff
8000697c:	00f5f5b3          	and	a1,a1,a5
  if((sz = uvmalloc(pagetable, sz, sz + 2*PGSIZE)) == 0) {
80006980:	00002637          	lui	a2,0x2
80006984:	00c58633          	add	a2,a1,a2
80006988:	000b0513          	mv	a0,s6
8000698c:	ffffb097          	auipc	ra,0xffffb
80006990:	158080e7          	jalr	344(ra) # 80001ae4 <uvmalloc>
80006994:	eca42e23          	sw	a0,-292(s0)
80006998:	02051663          	bnez	a0,800069c4 <exec+0x2a8>
  ip = 0;
8000699c:	00000a93          	li	s5,0
    fail_step = 11;
800069a0:	00b00593          	li	a1,11
  printf("exec fail step=%d path=%s\n", fail_step, path);
800069a4:	ed842603          	lw	a2,-296(s0)
800069a8:	00003517          	auipc	a0,0x3
800069ac:	d0850513          	addi	a0,a0,-760 # 800096b0 <userret+0x610>
800069b0:	ffffa097          	auipc	ra,0xffffa
800069b4:	da8080e7          	jalr	-600(ra) # 80000758 <printf>
  if(pagetable)
800069b8:	2100006f          	j	80006bc8 <exec+0x4ac>
  sz = 0;
800069bc:	ec042e23          	sw	zero,-292(s0)
800069c0:	f85ff06f          	j	80006944 <exec+0x228>
  uvmclear(pagetable, sz-2*PGSIZE);
800069c4:	ffffe5b7          	lui	a1,0xffffe
800069c8:	00b505b3          	add	a1,a0,a1
800069cc:	000b0513          	mv	a0,s6
800069d0:	ffffb097          	auipc	ra,0xffffb
800069d4:	3e0080e7          	jalr	992(ra) # 80001db0 <uvmclear>
  stackbase = sp - PGSIZE;
800069d8:	edc42783          	lw	a5,-292(s0)
800069dc:	80078a93          	addi	s5,a5,-2048 # ffffe800 <end+0x7ffda7ec>
800069e0:	800a8a93          	addi	s5,s5,-2048
  for(argc = 0; argv[argc]; argc++) {
800069e4:	ed442783          	lw	a5,-300(s0)
800069e8:	0007a503          	lw	a0,0(a5)
  sp = sz;
800069ec:	edc42903          	lw	s2,-292(s0)
  for(argc = 0; argv[argc]; argc++) {
800069f0:	00000493          	li	s1,0
    ustack[argc] = sp;
800069f4:	f3c40c13          	addi	s8,s0,-196
    if(argc >= MAXARG) {
800069f8:	02000b93          	li	s7,32
  for(argc = 0; argv[argc]; argc++) {
800069fc:	08050063          	beqz	a0,80006a7c <exec+0x360>
    sp -= strlen(argv[argc]) + 1;
80006a00:	ffffb097          	auipc	ra,0xffffb
80006a04:	804080e7          	jalr	-2044(ra) # 80001204 <strlen>
80006a08:	00150793          	addi	a5,a0,1
80006a0c:	40f907b3          	sub	a5,s2,a5
    sp -= sp % 16; // riscv sp must be 16-byte aligned
80006a10:	ff07f913          	andi	s2,a5,-16
    if(sp < stackbase) {
80006a14:	1f596663          	bltu	s2,s5,80006c00 <exec+0x4e4>
    if(copyout(pagetable, sp, argv[argc], strlen(argv[argc]) + 1) < 0) {
80006a18:	ed442783          	lw	a5,-300(s0)
80006a1c:	0007a983          	lw	s3,0(a5)
80006a20:	00098513          	mv	a0,s3
80006a24:	ffffa097          	auipc	ra,0xffffa
80006a28:	7e0080e7          	jalr	2016(ra) # 80001204 <strlen>
80006a2c:	00150693          	addi	a3,a0,1
80006a30:	00098613          	mv	a2,s3
80006a34:	00090593          	mv	a1,s2
80006a38:	000b0513          	mv	a0,s6
80006a3c:	ffffb097          	auipc	ra,0xffffb
80006a40:	3c0080e7          	jalr	960(ra) # 80001dfc <copyout>
80006a44:	1c054463          	bltz	a0,80006c0c <exec+0x4f0>
    ustack[argc] = sp;
80006a48:	00249793          	slli	a5,s1,0x2
80006a4c:	00fc07b3          	add	a5,s8,a5
80006a50:	0127a023          	sw	s2,0(a5)
  for(argc = 0; argv[argc]; argc++) {
80006a54:	00148493          	addi	s1,s1,1
80006a58:	ed442783          	lw	a5,-300(s0)
80006a5c:	00478793          	addi	a5,a5,4
80006a60:	ecf42a23          	sw	a5,-300(s0)
80006a64:	0007a503          	lw	a0,0(a5)
80006a68:	00050a63          	beqz	a0,80006a7c <exec+0x360>
    if(argc >= MAXARG) {
80006a6c:	f9749ae3          	bne	s1,s7,80006a00 <exec+0x2e4>
  ip = 0;
80006a70:	00000a93          	li	s5,0
      fail_step = 12;
80006a74:	00c00593          	li	a1,12
80006a78:	13c0006f          	j	80006bb4 <exec+0x498>
  ustack[argc] = 0;
80006a7c:	00249793          	slli	a5,s1,0x2
80006a80:	fd078793          	addi	a5,a5,-48
80006a84:	ff040713          	addi	a4,s0,-16
80006a88:	00e787b3          	add	a5,a5,a4
80006a8c:	f607ae23          	sw	zero,-132(a5)
  sp -= (argc+1) * sizeof(uint32);
80006a90:	00148693          	addi	a3,s1,1
80006a94:	00269693          	slli	a3,a3,0x2
80006a98:	40d90933          	sub	s2,s2,a3
  sp -= sp % 16;
80006a9c:	ff097913          	andi	s2,s2,-16
  if(sp < stackbase) {
80006aa0:	01597863          	bgeu	s2,s5,80006ab0 <exec+0x394>
  ip = 0;
80006aa4:	00000a93          	li	s5,0
    fail_step = 15;
80006aa8:	00f00593          	li	a1,15
80006aac:	ef9ff06f          	j	800069a4 <exec+0x288>
  if(copyout(pagetable, sp, (char *)ustack, (argc+1)*sizeof(uint32)) < 0) {
80006ab0:	f3c40613          	addi	a2,s0,-196
80006ab4:	00090593          	mv	a1,s2
80006ab8:	000b0513          	mv	a0,s6
80006abc:	ffffb097          	auipc	ra,0xffffb
80006ac0:	340080e7          	jalr	832(ra) # 80001dfc <copyout>
80006ac4:	16054863          	bltz	a0,80006c34 <exec+0x518>
  p->tf->a1 = sp;
80006ac8:	030a2783          	lw	a5,48(s4)
80006acc:	0327ae23          	sw	s2,60(a5)
  for(last=s=path; *s; s++)
80006ad0:	ed842783          	lw	a5,-296(s0)
80006ad4:	0007c703          	lbu	a4,0(a5)
80006ad8:	02070463          	beqz	a4,80006b00 <exec+0x3e4>
80006adc:	00178793          	addi	a5,a5,1
    if(*s == '/')
80006ae0:	02f00693          	li	a3,47
80006ae4:	0100006f          	j	80006af4 <exec+0x3d8>
  for(last=s=path; *s; s++)
80006ae8:	00178793          	addi	a5,a5,1
80006aec:	fff7c703          	lbu	a4,-1(a5)
80006af0:	00070863          	beqz	a4,80006b00 <exec+0x3e4>
    if(*s == '/')
80006af4:	fed71ae3          	bne	a4,a3,80006ae8 <exec+0x3cc>
      last = s+1;
80006af8:	ecf42c23          	sw	a5,-296(s0)
80006afc:	fedff06f          	j	80006ae8 <exec+0x3cc>
  safestrcpy(p->name, last, sizeof(p->name));
80006b00:	01000613          	li	a2,16
80006b04:	ed842583          	lw	a1,-296(s0)
80006b08:	0b0a0513          	addi	a0,s4,176
80006b0c:	ffffa097          	auipc	ra,0xffffa
80006b10:	6ac080e7          	jalr	1708(ra) # 800011b8 <safestrcpy>
  oldpagetable = p->pagetable;
80006b14:	02ca2503          	lw	a0,44(s4)
  p->pagetable = pagetable;
80006b18:	036a2623          	sw	s6,44(s4)
  p->sz = sz;
80006b1c:	edc42783          	lw	a5,-292(s0)
80006b20:	02fa2423          	sw	a5,40(s4)
  p->tf->epc = elf.entry;  // initial program counter = main
80006b24:	030a2783          	lw	a5,48(s4)
80006b28:	f2042703          	lw	a4,-224(s0)
80006b2c:	00e7a623          	sw	a4,12(a5)
  p->tf->sp = sp; // initial stack pointer
80006b30:	030a2783          	lw	a5,48(s4)
80006b34:	0127ac23          	sw	s2,24(a5)
  proc_freepagetable(oldpagetable, oldsz);
80006b38:	000c8593          	mv	a1,s9
80006b3c:	ffffc097          	auipc	ra,0xffffc
80006b40:	a20080e7          	jalr	-1504(ra) # 8000255c <proc_freepagetable>
  return argc; // this ends up in a0, the first argument to main(argc, argv)
80006b44:	00048513          	mv	a0,s1
80006b48:	11c12983          	lw	s3,284(sp)
80006b4c:	11812a03          	lw	s4,280(sp)
80006b50:	11412a83          	lw	s5,276(sp)
80006b54:	11012b03          	lw	s6,272(sp)
80006b58:	10c12b83          	lw	s7,268(sp)
80006b5c:	10812c03          	lw	s8,264(sp)
80006b60:	10412c83          	lw	s9,260(sp)
80006b64:	1100006f          	j	80006c74 <exec+0x558>
      fail_step = 5;
80006b68:	00500593          	li	a1,5
80006b6c:	10012d03          	lw	s10,256(sp)
80006b70:	0fc12d83          	lw	s11,252(sp)
80006b74:	0400006f          	j	80006bb4 <exec+0x498>
      fail_step = 6;
80006b78:	00600593          	li	a1,6
80006b7c:	10012d03          	lw	s10,256(sp)
80006b80:	0fc12d83          	lw	s11,252(sp)
80006b84:	0300006f          	j	80006bb4 <exec+0x498>
      fail_step = 7;
80006b88:	00700593          	li	a1,7
80006b8c:	10012d03          	lw	s10,256(sp)
80006b90:	0fc12d83          	lw	s11,252(sp)
80006b94:	0200006f          	j	80006bb4 <exec+0x498>
      fail_step = 8;
80006b98:	00800593          	li	a1,8
80006b9c:	10012d03          	lw	s10,256(sp)
80006ba0:	0fc12d83          	lw	s11,252(sp)
80006ba4:	0100006f          	j	80006bb4 <exec+0x498>
      fail_step = 10;
80006ba8:	00a00593          	li	a1,10
80006bac:	10012d03          	lw	s10,256(sp)
80006bb0:	0fc12d83          	lw	s11,252(sp)
  printf("exec fail step=%d path=%s\n", fail_step, path);
80006bb4:	ed842603          	lw	a2,-296(s0)
80006bb8:	00003517          	auipc	a0,0x3
80006bbc:	af850513          	addi	a0,a0,-1288 # 800096b0 <userret+0x610>
80006bc0:	ffffa097          	auipc	ra,0xffffa
80006bc4:	b98080e7          	jalr	-1128(ra) # 80000758 <printf>
    proc_freepagetable(pagetable, sz);
80006bc8:	edc42583          	lw	a1,-292(s0)
80006bcc:	000b0513          	mv	a0,s6
80006bd0:	ffffc097          	auipc	ra,0xffffc
80006bd4:	98c080e7          	jalr	-1652(ra) # 8000255c <proc_freepagetable>
  return -1;
80006bd8:	fff00513          	li	a0,-1
  if(ip){
80006bdc:	020a9e63          	bnez	s5,80006c18 <exec+0x4fc>
80006be0:	11c12983          	lw	s3,284(sp)
80006be4:	11812a03          	lw	s4,280(sp)
80006be8:	11412a83          	lw	s5,276(sp)
80006bec:	11012b03          	lw	s6,272(sp)
80006bf0:	10c12b83          	lw	s7,268(sp)
80006bf4:	10812c03          	lw	s8,264(sp)
80006bf8:	10412c83          	lw	s9,260(sp)
80006bfc:	0780006f          	j	80006c74 <exec+0x558>
  ip = 0;
80006c00:	00000a93          	li	s5,0
      fail_step = 13;
80006c04:	00d00593          	li	a1,13
80006c08:	fadff06f          	j	80006bb4 <exec+0x498>
  ip = 0;
80006c0c:	00000a93          	li	s5,0
      fail_step = 14;
80006c10:	00e00593          	li	a1,14
80006c14:	fa1ff06f          	j	80006bb4 <exec+0x498>
80006c18:	11c12983          	lw	s3,284(sp)
80006c1c:	11812a03          	lw	s4,280(sp)
80006c20:	11012b03          	lw	s6,272(sp)
80006c24:	10c12b83          	lw	s7,268(sp)
80006c28:	10812c03          	lw	s8,264(sp)
80006c2c:	10412c83          	lw	s9,260(sp)
80006c30:	0280006f          	j	80006c58 <exec+0x53c>
  ip = 0;
80006c34:	00000a93          	li	s5,0
    fail_step = 16;
80006c38:	01000593          	li	a1,16
80006c3c:	d69ff06f          	j	800069a4 <exec+0x288>
    fail_step = 2;
80006c40:	00200593          	li	a1,2
  printf("exec fail step=%d path=%s\n", fail_step, path);
80006c44:	ed842603          	lw	a2,-296(s0)
80006c48:	00003517          	auipc	a0,0x3
80006c4c:	a6850513          	addi	a0,a0,-1432 # 800096b0 <userret+0x610>
80006c50:	ffffa097          	auipc	ra,0xffffa
80006c54:	b08080e7          	jalr	-1272(ra) # 80000758 <printf>
    iunlockput(ip);
80006c58:	000a8513          	mv	a0,s5
80006c5c:	ffffe097          	auipc	ra,0xffffe
80006c60:	f6c080e7          	jalr	-148(ra) # 80004bc8 <iunlockput>
    end_op();
80006c64:	fffff097          	auipc	ra,0xfffff
80006c68:	ac8080e7          	jalr	-1336(ra) # 8000572c <end_op>
  return -1;
80006c6c:	fff00513          	li	a0,-1
80006c70:	11412a83          	lw	s5,276(sp)
}
80006c74:	12c12083          	lw	ra,300(sp)
80006c78:	12812403          	lw	s0,296(sp)
80006c7c:	12412483          	lw	s1,292(sp)
80006c80:	12012903          	lw	s2,288(sp)
80006c84:	13010113          	addi	sp,sp,304
80006c88:	00008067          	ret
    fail_step = 4;
80006c8c:	00400593          	li	a1,4
80006c90:	11012b03          	lw	s6,272(sp)
80006c94:	fb1ff06f          	j	80006c44 <exec+0x528>

80006c98 <argfd>:

// Fetch the nth word-sized system call argument as a file descriptor
// and return both the descriptor and the corresponding struct file.
static int
argfd(int n, int *pfd, struct file **pf)
{
80006c98:	fe010113          	addi	sp,sp,-32
80006c9c:	00112e23          	sw	ra,28(sp)
80006ca0:	00812c23          	sw	s0,24(sp)
80006ca4:	00912a23          	sw	s1,20(sp)
80006ca8:	01212823          	sw	s2,16(sp)
80006cac:	02010413          	addi	s0,sp,32
80006cb0:	00058913          	mv	s2,a1
80006cb4:	00060493          	mv	s1,a2
  int fd;
  struct file *f;

  if(argint(n, &fd) < 0)
80006cb8:	fec40593          	addi	a1,s0,-20
80006cbc:	ffffd097          	auipc	ra,0xffffd
80006cc0:	c84080e7          	jalr	-892(ra) # 80003940 <argint>
80006cc4:	04054e63          	bltz	a0,80006d20 <argfd+0x88>
    return -1;
  if(fd < 0 || fd >= NOFILE || (f=myproc()->ofile[fd]) == 0)
80006cc8:	fec42703          	lw	a4,-20(s0)
80006ccc:	00f00793          	li	a5,15
80006cd0:	04e7ec63          	bltu	a5,a4,80006d28 <argfd+0x90>
80006cd4:	ffffb097          	auipc	ra,0xffffb
80006cd8:	608080e7          	jalr	1544(ra) # 800022dc <myproc>
80006cdc:	fec42703          	lw	a4,-20(s0)
80006ce0:	01870793          	addi	a5,a4,24
80006ce4:	00279793          	slli	a5,a5,0x2
80006ce8:	00f50533          	add	a0,a0,a5
80006cec:	00c52783          	lw	a5,12(a0)
80006cf0:	04078063          	beqz	a5,80006d30 <argfd+0x98>
    return -1;
  if(pfd)
80006cf4:	00090463          	beqz	s2,80006cfc <argfd+0x64>
    *pfd = fd;
80006cf8:	00e92023          	sw	a4,0(s2)
  if(pf)
    *pf = f;
  return 0;
80006cfc:	00000513          	li	a0,0
  if(pf)
80006d00:	00048463          	beqz	s1,80006d08 <argfd+0x70>
    *pf = f;
80006d04:	00f4a023          	sw	a5,0(s1)
}
80006d08:	01c12083          	lw	ra,28(sp)
80006d0c:	01812403          	lw	s0,24(sp)
80006d10:	01412483          	lw	s1,20(sp)
80006d14:	01012903          	lw	s2,16(sp)
80006d18:	02010113          	addi	sp,sp,32
80006d1c:	00008067          	ret
    return -1;
80006d20:	fff00513          	li	a0,-1
80006d24:	fe5ff06f          	j	80006d08 <argfd+0x70>
    return -1;
80006d28:	fff00513          	li	a0,-1
80006d2c:	fddff06f          	j	80006d08 <argfd+0x70>
80006d30:	fff00513          	li	a0,-1
80006d34:	fd5ff06f          	j	80006d08 <argfd+0x70>

80006d38 <fdalloc>:

// Allocate a file descriptor for the given file.
// Takes over file reference from caller on success.
static int
fdalloc(struct file *f)
{
80006d38:	ff010113          	addi	sp,sp,-16
80006d3c:	00112623          	sw	ra,12(sp)
80006d40:	00812423          	sw	s0,8(sp)
80006d44:	00912223          	sw	s1,4(sp)
80006d48:	01010413          	addi	s0,sp,16
80006d4c:	00050493          	mv	s1,a0
  int fd;
  struct proc *p = myproc();
80006d50:	ffffb097          	auipc	ra,0xffffb
80006d54:	58c080e7          	jalr	1420(ra) # 800022dc <myproc>
80006d58:	00050613          	mv	a2,a0

  for(fd = 0; fd < NOFILE; fd++){
80006d5c:	06c50793          	addi	a5,a0,108
80006d60:	00000513          	li	a0,0
80006d64:	01000693          	li	a3,16
    if(p->ofile[fd] == 0){
80006d68:	0007a703          	lw	a4,0(a5)
80006d6c:	02070463          	beqz	a4,80006d94 <fdalloc+0x5c>
  for(fd = 0; fd < NOFILE; fd++){
80006d70:	00150513          	addi	a0,a0,1
80006d74:	00478793          	addi	a5,a5,4
80006d78:	fed518e3          	bne	a0,a3,80006d68 <fdalloc+0x30>
      p->ofile[fd] = f;
      return fd;
    }
  }
  return -1;
80006d7c:	fff00513          	li	a0,-1
}
80006d80:	00c12083          	lw	ra,12(sp)
80006d84:	00812403          	lw	s0,8(sp)
80006d88:	00412483          	lw	s1,4(sp)
80006d8c:	01010113          	addi	sp,sp,16
80006d90:	00008067          	ret
      p->ofile[fd] = f;
80006d94:	01850793          	addi	a5,a0,24
80006d98:	00279793          	slli	a5,a5,0x2
80006d9c:	00f60633          	add	a2,a2,a5
80006da0:	00962623          	sw	s1,12(a2) # 200c <_entry-0x7fffdff4>
      return fd;
80006da4:	fddff06f          	j	80006d80 <fdalloc+0x48>

80006da8 <create>:
  return -1;
}

static struct inode*
create(char *path, short type, short major, short minor)
{
80006da8:	fd010113          	addi	sp,sp,-48
80006dac:	02112623          	sw	ra,44(sp)
80006db0:	02812423          	sw	s0,40(sp)
80006db4:	02912223          	sw	s1,36(sp)
80006db8:	03212023          	sw	s2,32(sp)
80006dbc:	01312e23          	sw	s3,28(sp)
80006dc0:	01412c23          	sw	s4,24(sp)
80006dc4:	01512a23          	sw	s5,20(sp)
80006dc8:	03010413          	addi	s0,sp,48
80006dcc:	00058993          	mv	s3,a1
80006dd0:	00060a13          	mv	s4,a2
80006dd4:	00068a93          	mv	s5,a3
  struct inode *ip, *dp;
  char name[DIRSIZ];

  if((dp = nameiparent(path, name)) == 0)
80006dd8:	fd040593          	addi	a1,s0,-48
80006ddc:	ffffe097          	auipc	ra,0xffffe
80006de0:	608080e7          	jalr	1544(ra) # 800053e4 <nameiparent>
80006de4:	00050913          	mv	s2,a0
80006de8:	18050463          	beqz	a0,80006f70 <create+0x1c8>
    return 0;

  ilock(dp);
80006dec:	ffffe097          	auipc	ra,0xffffe
80006df0:	acc080e7          	jalr	-1332(ra) # 800048b8 <ilock>

  if((ip = dirlookup(dp, name, 0)) != 0){
80006df4:	00000613          	li	a2,0
80006df8:	fd040593          	addi	a1,s0,-48
80006dfc:	00090513          	mv	a0,s2
80006e00:	ffffe097          	auipc	ra,0xffffe
80006e04:	154080e7          	jalr	340(ra) # 80004f54 <dirlookup>
80006e08:	00050493          	mv	s1,a0
80006e0c:	06050c63          	beqz	a0,80006e84 <create+0xdc>
    iunlockput(dp);
80006e10:	00090513          	mv	a0,s2
80006e14:	ffffe097          	auipc	ra,0xffffe
80006e18:	db4080e7          	jalr	-588(ra) # 80004bc8 <iunlockput>
    ilock(ip);
80006e1c:	00048513          	mv	a0,s1
80006e20:	ffffe097          	auipc	ra,0xffffe
80006e24:	a98080e7          	jalr	-1384(ra) # 800048b8 <ilock>
    if(type == T_FILE && (ip->type == T_FILE || ip->type == T_DEVICE))
80006e28:	00200793          	li	a5,2
80006e2c:	04f99263          	bne	s3,a5,80006e70 <create+0xc8>
80006e30:	0284d783          	lhu	a5,40(s1)
80006e34:	ffe78793          	addi	a5,a5,-2
80006e38:	01079793          	slli	a5,a5,0x10
80006e3c:	0107d793          	srli	a5,a5,0x10
80006e40:	00100713          	li	a4,1
80006e44:	02f76663          	bltu	a4,a5,80006e70 <create+0xc8>
    panic("create: dirlink");

  iunlockput(dp);

  return ip;
}
80006e48:	00048513          	mv	a0,s1
80006e4c:	02c12083          	lw	ra,44(sp)
80006e50:	02812403          	lw	s0,40(sp)
80006e54:	02412483          	lw	s1,36(sp)
80006e58:	02012903          	lw	s2,32(sp)
80006e5c:	01c12983          	lw	s3,28(sp)
80006e60:	01812a03          	lw	s4,24(sp)
80006e64:	01412a83          	lw	s5,20(sp)
80006e68:	03010113          	addi	sp,sp,48
80006e6c:	00008067          	ret
    iunlockput(ip);
80006e70:	00048513          	mv	a0,s1
80006e74:	ffffe097          	auipc	ra,0xffffe
80006e78:	d54080e7          	jalr	-684(ra) # 80004bc8 <iunlockput>
    return 0;
80006e7c:	00000493          	li	s1,0
80006e80:	fc9ff06f          	j	80006e48 <create+0xa0>
  if((ip = ialloc(dp->dev, type)) == 0)
80006e84:	00098593          	mv	a1,s3
80006e88:	00092503          	lw	a0,0(s2)
80006e8c:	ffffe097          	auipc	ra,0xffffe
80006e90:	804080e7          	jalr	-2044(ra) # 80004690 <ialloc>
80006e94:	00050493          	mv	s1,a0
80006e98:	04050c63          	beqz	a0,80006ef0 <create+0x148>
  ilock(ip);
80006e9c:	ffffe097          	auipc	ra,0xffffe
80006ea0:	a1c080e7          	jalr	-1508(ra) # 800048b8 <ilock>
  ip->major = major;
80006ea4:	03449523          	sh	s4,42(s1)
  ip->minor = minor;
80006ea8:	03549623          	sh	s5,44(s1)
  ip->nlink = 1;
80006eac:	00100793          	li	a5,1
80006eb0:	02f49723          	sh	a5,46(s1)
  iupdate(ip);
80006eb4:	00048513          	mv	a0,s1
80006eb8:	ffffe097          	auipc	ra,0xffffe
80006ebc:	8e4080e7          	jalr	-1820(ra) # 8000479c <iupdate>
  if(type == T_DIR){  // Create . and .. entries.
80006ec0:	00100713          	li	a4,1
80006ec4:	02e98e63          	beq	s3,a4,80006f00 <create+0x158>
  if(dirlink(dp, name, ip->inum) < 0)
80006ec8:	0044a603          	lw	a2,4(s1)
80006ecc:	fd040593          	addi	a1,s0,-48
80006ed0:	00090513          	mv	a0,s2
80006ed4:	ffffe097          	auipc	ra,0xffffe
80006ed8:	3a4080e7          	jalr	932(ra) # 80005278 <dirlink>
80006edc:	08054263          	bltz	a0,80006f60 <create+0x1b8>
  iunlockput(dp);
80006ee0:	00090513          	mv	a0,s2
80006ee4:	ffffe097          	auipc	ra,0xffffe
80006ee8:	ce4080e7          	jalr	-796(ra) # 80004bc8 <iunlockput>
  return ip;
80006eec:	f5dff06f          	j	80006e48 <create+0xa0>
    panic("create: ialloc");
80006ef0:	00002517          	auipc	a0,0x2
80006ef4:	7dc50513          	addi	a0,a0,2012 # 800096cc <userret+0x62c>
80006ef8:	ffffa097          	auipc	ra,0xffffa
80006efc:	804080e7          	jalr	-2044(ra) # 800006fc <panic>
    dp->nlink++;  // for ".."
80006f00:	02e95783          	lhu	a5,46(s2)
80006f04:	00e787b3          	add	a5,a5,a4
80006f08:	02f91723          	sh	a5,46(s2)
    iupdate(dp);
80006f0c:	00090513          	mv	a0,s2
80006f10:	ffffe097          	auipc	ra,0xffffe
80006f14:	88c080e7          	jalr	-1908(ra) # 8000479c <iupdate>
    if(dirlink(ip, ".", ip->inum) < 0 || dirlink(ip, "..", dp->inum) < 0)
80006f18:	0044a603          	lw	a2,4(s1)
80006f1c:	00002597          	auipc	a1,0x2
80006f20:	7c058593          	addi	a1,a1,1984 # 800096dc <userret+0x63c>
80006f24:	00048513          	mv	a0,s1
80006f28:	ffffe097          	auipc	ra,0xffffe
80006f2c:	350080e7          	jalr	848(ra) # 80005278 <dirlink>
80006f30:	02054063          	bltz	a0,80006f50 <create+0x1a8>
80006f34:	00492603          	lw	a2,4(s2)
80006f38:	00002597          	auipc	a1,0x2
80006f3c:	7a858593          	addi	a1,a1,1960 # 800096e0 <userret+0x640>
80006f40:	00048513          	mv	a0,s1
80006f44:	ffffe097          	auipc	ra,0xffffe
80006f48:	334080e7          	jalr	820(ra) # 80005278 <dirlink>
80006f4c:	f6055ee3          	bgez	a0,80006ec8 <create+0x120>
      panic("create dots");
80006f50:	00002517          	auipc	a0,0x2
80006f54:	79450513          	addi	a0,a0,1940 # 800096e4 <userret+0x644>
80006f58:	ffff9097          	auipc	ra,0xffff9
80006f5c:	7a4080e7          	jalr	1956(ra) # 800006fc <panic>
    panic("create: dirlink");
80006f60:	00002517          	auipc	a0,0x2
80006f64:	79050513          	addi	a0,a0,1936 # 800096f0 <userret+0x650>
80006f68:	ffff9097          	auipc	ra,0xffff9
80006f6c:	794080e7          	jalr	1940(ra) # 800006fc <panic>
    return 0;
80006f70:	00050493          	mv	s1,a0
80006f74:	ed5ff06f          	j	80006e48 <create+0xa0>

80006f78 <sys_dup>:
{
80006f78:	fe010113          	addi	sp,sp,-32
80006f7c:	00112e23          	sw	ra,28(sp)
80006f80:	00812c23          	sw	s0,24(sp)
80006f84:	02010413          	addi	s0,sp,32
  if(argfd(0, 0, &f) < 0)
80006f88:	fec40613          	addi	a2,s0,-20
80006f8c:	00000593          	li	a1,0
80006f90:	00000513          	li	a0,0
80006f94:	00000097          	auipc	ra,0x0
80006f98:	d04080e7          	jalr	-764(ra) # 80006c98 <argfd>
    return -1;
80006f9c:	fff00793          	li	a5,-1
  if(argfd(0, 0, &f) < 0)
80006fa0:	04054263          	bltz	a0,80006fe4 <sys_dup+0x6c>
80006fa4:	00912a23          	sw	s1,20(sp)
80006fa8:	01212823          	sw	s2,16(sp)
  if((fd=fdalloc(f)) < 0)
80006fac:	fec42783          	lw	a5,-20(s0)
80006fb0:	00078493          	mv	s1,a5
80006fb4:	00078513          	mv	a0,a5
80006fb8:	00000097          	auipc	ra,0x0
80006fbc:	d80080e7          	jalr	-640(ra) # 80006d38 <fdalloc>
80006fc0:	00050913          	mv	s2,a0
    return -1;
80006fc4:	fff00793          	li	a5,-1
  if((fd=fdalloc(f)) < 0)
80006fc8:	02054863          	bltz	a0,80006ff8 <sys_dup+0x80>
  filedup(f);
80006fcc:	00048513          	mv	a0,s1
80006fd0:	fffff097          	auipc	ra,0xfffff
80006fd4:	cd4080e7          	jalr	-812(ra) # 80005ca4 <filedup>
  return fd;
80006fd8:	00090793          	mv	a5,s2
80006fdc:	01412483          	lw	s1,20(sp)
80006fe0:	01012903          	lw	s2,16(sp)
}
80006fe4:	00078513          	mv	a0,a5
80006fe8:	01c12083          	lw	ra,28(sp)
80006fec:	01812403          	lw	s0,24(sp)
80006ff0:	02010113          	addi	sp,sp,32
80006ff4:	00008067          	ret
80006ff8:	01412483          	lw	s1,20(sp)
80006ffc:	01012903          	lw	s2,16(sp)
80007000:	fe5ff06f          	j	80006fe4 <sys_dup+0x6c>

80007004 <sys_read>:
{
80007004:	fe010113          	addi	sp,sp,-32
80007008:	00112e23          	sw	ra,28(sp)
8000700c:	00812c23          	sw	s0,24(sp)
80007010:	02010413          	addi	s0,sp,32
  if(argfd(0, 0, &f) < 0 || argint(2, &n) < 0 || argaddr(1, &p) < 0)
80007014:	fec40613          	addi	a2,s0,-20
80007018:	00000593          	li	a1,0
8000701c:	00000513          	li	a0,0
80007020:	00000097          	auipc	ra,0x0
80007024:	c78080e7          	jalr	-904(ra) # 80006c98 <argfd>
    return -1;
80007028:	fff00793          	li	a5,-1
  if(argfd(0, 0, &f) < 0 || argint(2, &n) < 0 || argaddr(1, &p) < 0)
8000702c:	04054663          	bltz	a0,80007078 <sys_read+0x74>
80007030:	fe840593          	addi	a1,s0,-24
80007034:	00200513          	li	a0,2
80007038:	ffffd097          	auipc	ra,0xffffd
8000703c:	908080e7          	jalr	-1784(ra) # 80003940 <argint>
    return -1;
80007040:	fff00793          	li	a5,-1
  if(argfd(0, 0, &f) < 0 || argint(2, &n) < 0 || argaddr(1, &p) < 0)
80007044:	02054a63          	bltz	a0,80007078 <sys_read+0x74>
80007048:	fe440593          	addi	a1,s0,-28
8000704c:	00100513          	li	a0,1
80007050:	ffffd097          	auipc	ra,0xffffd
80007054:	92c080e7          	jalr	-1748(ra) # 8000397c <argaddr>
    return -1;
80007058:	fff00793          	li	a5,-1
  if(argfd(0, 0, &f) < 0 || argint(2, &n) < 0 || argaddr(1, &p) < 0)
8000705c:	00054e63          	bltz	a0,80007078 <sys_read+0x74>
  return fileread(f, p, n);
80007060:	fe842603          	lw	a2,-24(s0)
80007064:	fe442583          	lw	a1,-28(s0)
80007068:	fec42503          	lw	a0,-20(s0)
8000706c:	fffff097          	auipc	ra,0xfffff
80007070:	ea0080e7          	jalr	-352(ra) # 80005f0c <fileread>
80007074:	00050793          	mv	a5,a0
}
80007078:	00078513          	mv	a0,a5
8000707c:	01c12083          	lw	ra,28(sp)
80007080:	01812403          	lw	s0,24(sp)
80007084:	02010113          	addi	sp,sp,32
80007088:	00008067          	ret

8000708c <sys_write>:
{
8000708c:	fe010113          	addi	sp,sp,-32
80007090:	00112e23          	sw	ra,28(sp)
80007094:	00812c23          	sw	s0,24(sp)
80007098:	02010413          	addi	s0,sp,32
  if(argfd(0, 0, &f) < 0 || argint(2, &n) < 0 || argaddr(1, &p) < 0)
8000709c:	fec40613          	addi	a2,s0,-20
800070a0:	00000593          	li	a1,0
800070a4:	00000513          	li	a0,0
800070a8:	00000097          	auipc	ra,0x0
800070ac:	bf0080e7          	jalr	-1040(ra) # 80006c98 <argfd>
    return -1;
800070b0:	fff00793          	li	a5,-1
  if(argfd(0, 0, &f) < 0 || argint(2, &n) < 0 || argaddr(1, &p) < 0)
800070b4:	04054663          	bltz	a0,80007100 <sys_write+0x74>
800070b8:	fe840593          	addi	a1,s0,-24
800070bc:	00200513          	li	a0,2
800070c0:	ffffd097          	auipc	ra,0xffffd
800070c4:	880080e7          	jalr	-1920(ra) # 80003940 <argint>
    return -1;
800070c8:	fff00793          	li	a5,-1
  if(argfd(0, 0, &f) < 0 || argint(2, &n) < 0 || argaddr(1, &p) < 0)
800070cc:	02054a63          	bltz	a0,80007100 <sys_write+0x74>
800070d0:	fe440593          	addi	a1,s0,-28
800070d4:	00100513          	li	a0,1
800070d8:	ffffd097          	auipc	ra,0xffffd
800070dc:	8a4080e7          	jalr	-1884(ra) # 8000397c <argaddr>
    return -1;
800070e0:	fff00793          	li	a5,-1
  if(argfd(0, 0, &f) < 0 || argint(2, &n) < 0 || argaddr(1, &p) < 0)
800070e4:	00054e63          	bltz	a0,80007100 <sys_write+0x74>
  return filewrite(f, p, n);
800070e8:	fe842603          	lw	a2,-24(s0)
800070ec:	fe442583          	lw	a1,-28(s0)
800070f0:	fec42503          	lw	a0,-20(s0)
800070f4:	fffff097          	auipc	ra,0xfffff
800070f8:	f70080e7          	jalr	-144(ra) # 80006064 <filewrite>
800070fc:	00050793          	mv	a5,a0
}
80007100:	00078513          	mv	a0,a5
80007104:	01c12083          	lw	ra,28(sp)
80007108:	01812403          	lw	s0,24(sp)
8000710c:	02010113          	addi	sp,sp,32
80007110:	00008067          	ret

80007114 <sys_close>:
{
80007114:	fe010113          	addi	sp,sp,-32
80007118:	00112e23          	sw	ra,28(sp)
8000711c:	00812c23          	sw	s0,24(sp)
80007120:	02010413          	addi	s0,sp,32
  if(argfd(0, &fd, &f) < 0)
80007124:	fe840613          	addi	a2,s0,-24
80007128:	fec40593          	addi	a1,s0,-20
8000712c:	00000513          	li	a0,0
80007130:	00000097          	auipc	ra,0x0
80007134:	b68080e7          	jalr	-1176(ra) # 80006c98 <argfd>
    return -1;
80007138:	fff00793          	li	a5,-1
  if(argfd(0, &fd, &f) < 0)
8000713c:	02054863          	bltz	a0,8000716c <sys_close+0x58>
  myproc()->ofile[fd] = 0;
80007140:	ffffb097          	auipc	ra,0xffffb
80007144:	19c080e7          	jalr	412(ra) # 800022dc <myproc>
80007148:	fec42783          	lw	a5,-20(s0)
8000714c:	01878793          	addi	a5,a5,24
80007150:	00279793          	slli	a5,a5,0x2
80007154:	00f50533          	add	a0,a0,a5
80007158:	00052623          	sw	zero,12(a0)
  fileclose(f);
8000715c:	fe842503          	lw	a0,-24(s0)
80007160:	fffff097          	auipc	ra,0xfffff
80007164:	bb4080e7          	jalr	-1100(ra) # 80005d14 <fileclose>
  return 0;
80007168:	00000793          	li	a5,0
}
8000716c:	00078513          	mv	a0,a5
80007170:	01c12083          	lw	ra,28(sp)
80007174:	01812403          	lw	s0,24(sp)
80007178:	02010113          	addi	sp,sp,32
8000717c:	00008067          	ret

80007180 <sys_fstat>:
{
80007180:	fe010113          	addi	sp,sp,-32
80007184:	00112e23          	sw	ra,28(sp)
80007188:	00812c23          	sw	s0,24(sp)
8000718c:	02010413          	addi	s0,sp,32
  if(argfd(0, 0, &f) < 0 || argaddr(1, &st) < 0)
80007190:	fec40613          	addi	a2,s0,-20
80007194:	00000593          	li	a1,0
80007198:	00000513          	li	a0,0
8000719c:	00000097          	auipc	ra,0x0
800071a0:	afc080e7          	jalr	-1284(ra) # 80006c98 <argfd>
    return -1;
800071a4:	fff00793          	li	a5,-1
  if(argfd(0, 0, &f) < 0 || argaddr(1, &st) < 0)
800071a8:	02054863          	bltz	a0,800071d8 <sys_fstat+0x58>
800071ac:	fe840593          	addi	a1,s0,-24
800071b0:	00100513          	li	a0,1
800071b4:	ffffc097          	auipc	ra,0xffffc
800071b8:	7c8080e7          	jalr	1992(ra) # 8000397c <argaddr>
    return -1;
800071bc:	fff00793          	li	a5,-1
  if(argfd(0, 0, &f) < 0 || argaddr(1, &st) < 0)
800071c0:	00054c63          	bltz	a0,800071d8 <sys_fstat+0x58>
  return filestat(f, st);
800071c4:	fe842583          	lw	a1,-24(s0)
800071c8:	fec42503          	lw	a0,-20(s0)
800071cc:	fffff097          	auipc	ra,0xfffff
800071d0:	c8c080e7          	jalr	-884(ra) # 80005e58 <filestat>
800071d4:	00050793          	mv	a5,a0
}
800071d8:	00078513          	mv	a0,a5
800071dc:	01c12083          	lw	ra,28(sp)
800071e0:	01812403          	lw	s0,24(sp)
800071e4:	02010113          	addi	sp,sp,32
800071e8:	00008067          	ret

800071ec <sys_link>:
{
800071ec:	ee010113          	addi	sp,sp,-288
800071f0:	10112e23          	sw	ra,284(sp)
800071f4:	10812c23          	sw	s0,280(sp)
800071f8:	12010413          	addi	s0,sp,288
  if(argstr(0, old, MAXPATH) < 0 || argstr(1, new, MAXPATH) < 0)
800071fc:	08000613          	li	a2,128
80007200:	ee040593          	addi	a1,s0,-288
80007204:	00000513          	li	a0,0
80007208:	ffffc097          	auipc	ra,0xffffc
8000720c:	7b0080e7          	jalr	1968(ra) # 800039b8 <argstr>
    return -1;
80007210:	fff00793          	li	a5,-1
  if(argstr(0, old, MAXPATH) < 0 || argstr(1, new, MAXPATH) < 0)
80007214:	16054a63          	bltz	a0,80007388 <sys_link+0x19c>
80007218:	08000613          	li	a2,128
8000721c:	f6040593          	addi	a1,s0,-160
80007220:	00100513          	li	a0,1
80007224:	ffffc097          	auipc	ra,0xffffc
80007228:	794080e7          	jalr	1940(ra) # 800039b8 <argstr>
    return -1;
8000722c:	fff00793          	li	a5,-1
  if(argstr(0, old, MAXPATH) < 0 || argstr(1, new, MAXPATH) < 0)
80007230:	14054c63          	bltz	a0,80007388 <sys_link+0x19c>
80007234:	10912a23          	sw	s1,276(sp)
  begin_op();
80007238:	ffffe097          	auipc	ra,0xffffe
8000723c:	440080e7          	jalr	1088(ra) # 80005678 <begin_op>
  if((ip = namei(old)) == 0){
80007240:	ee040513          	addi	a0,s0,-288
80007244:	ffffe097          	auipc	ra,0xffffe
80007248:	170080e7          	jalr	368(ra) # 800053b4 <namei>
8000724c:	00050493          	mv	s1,a0
80007250:	0a050a63          	beqz	a0,80007304 <sys_link+0x118>
  ilock(ip);
80007254:	ffffd097          	auipc	ra,0xffffd
80007258:	664080e7          	jalr	1636(ra) # 800048b8 <ilock>
  if(ip->type == T_DIR){
8000725c:	02849703          	lh	a4,40(s1)
80007260:	00100793          	li	a5,1
80007264:	0af70a63          	beq	a4,a5,80007318 <sys_link+0x12c>
80007268:	11212823          	sw	s2,272(sp)
  ip->nlink++;
8000726c:	02e4d783          	lhu	a5,46(s1)
80007270:	00178793          	addi	a5,a5,1
80007274:	02f49723          	sh	a5,46(s1)
  iupdate(ip);
80007278:	00048513          	mv	a0,s1
8000727c:	ffffd097          	auipc	ra,0xffffd
80007280:	520080e7          	jalr	1312(ra) # 8000479c <iupdate>
  iunlock(ip);
80007284:	00048513          	mv	a0,s1
80007288:	ffffd097          	auipc	ra,0xffffd
8000728c:	73c080e7          	jalr	1852(ra) # 800049c4 <iunlock>
  if((dp = nameiparent(new, name)) == 0)
80007290:	fe040593          	addi	a1,s0,-32
80007294:	f6040513          	addi	a0,s0,-160
80007298:	ffffe097          	auipc	ra,0xffffe
8000729c:	14c080e7          	jalr	332(ra) # 800053e4 <nameiparent>
800072a0:	00050913          	mv	s2,a0
800072a4:	0a050063          	beqz	a0,80007344 <sys_link+0x158>
  ilock(dp);
800072a8:	ffffd097          	auipc	ra,0xffffd
800072ac:	610080e7          	jalr	1552(ra) # 800048b8 <ilock>
  if(dp->dev != ip->dev || dirlink(dp, name, ip->inum) < 0){
800072b0:	00092703          	lw	a4,0(s2)
800072b4:	0004a783          	lw	a5,0(s1)
800072b8:	08f71063          	bne	a4,a5,80007338 <sys_link+0x14c>
800072bc:	0044a603          	lw	a2,4(s1)
800072c0:	fe040593          	addi	a1,s0,-32
800072c4:	00090513          	mv	a0,s2
800072c8:	ffffe097          	auipc	ra,0xffffe
800072cc:	fb0080e7          	jalr	-80(ra) # 80005278 <dirlink>
800072d0:	06054463          	bltz	a0,80007338 <sys_link+0x14c>
  iunlockput(dp);
800072d4:	00090513          	mv	a0,s2
800072d8:	ffffe097          	auipc	ra,0xffffe
800072dc:	8f0080e7          	jalr	-1808(ra) # 80004bc8 <iunlockput>
  iput(ip);
800072e0:	00048513          	mv	a0,s1
800072e4:	ffffd097          	auipc	ra,0xffffd
800072e8:	750080e7          	jalr	1872(ra) # 80004a34 <iput>
  end_op();
800072ec:	ffffe097          	auipc	ra,0xffffe
800072f0:	440080e7          	jalr	1088(ra) # 8000572c <end_op>
  return 0;
800072f4:	00000793          	li	a5,0
800072f8:	11412483          	lw	s1,276(sp)
800072fc:	11012903          	lw	s2,272(sp)
80007300:	0880006f          	j	80007388 <sys_link+0x19c>
    end_op();
80007304:	ffffe097          	auipc	ra,0xffffe
80007308:	428080e7          	jalr	1064(ra) # 8000572c <end_op>
    return -1;
8000730c:	fff00793          	li	a5,-1
80007310:	11412483          	lw	s1,276(sp)
80007314:	0740006f          	j	80007388 <sys_link+0x19c>
    iunlockput(ip);
80007318:	00048513          	mv	a0,s1
8000731c:	ffffe097          	auipc	ra,0xffffe
80007320:	8ac080e7          	jalr	-1876(ra) # 80004bc8 <iunlockput>
    end_op();
80007324:	ffffe097          	auipc	ra,0xffffe
80007328:	408080e7          	jalr	1032(ra) # 8000572c <end_op>
    return -1;
8000732c:	fff00793          	li	a5,-1
80007330:	11412483          	lw	s1,276(sp)
80007334:	0540006f          	j	80007388 <sys_link+0x19c>
    iunlockput(dp);
80007338:	00090513          	mv	a0,s2
8000733c:	ffffe097          	auipc	ra,0xffffe
80007340:	88c080e7          	jalr	-1908(ra) # 80004bc8 <iunlockput>
  ilock(ip);
80007344:	00048513          	mv	a0,s1
80007348:	ffffd097          	auipc	ra,0xffffd
8000734c:	570080e7          	jalr	1392(ra) # 800048b8 <ilock>
  ip->nlink--;
80007350:	02e4d783          	lhu	a5,46(s1)
80007354:	fff78793          	addi	a5,a5,-1
80007358:	02f49723          	sh	a5,46(s1)
  iupdate(ip);
8000735c:	00048513          	mv	a0,s1
80007360:	ffffd097          	auipc	ra,0xffffd
80007364:	43c080e7          	jalr	1084(ra) # 8000479c <iupdate>
  iunlockput(ip);
80007368:	00048513          	mv	a0,s1
8000736c:	ffffe097          	auipc	ra,0xffffe
80007370:	85c080e7          	jalr	-1956(ra) # 80004bc8 <iunlockput>
  end_op();
80007374:	ffffe097          	auipc	ra,0xffffe
80007378:	3b8080e7          	jalr	952(ra) # 8000572c <end_op>
  return -1;
8000737c:	fff00793          	li	a5,-1
80007380:	11412483          	lw	s1,276(sp)
80007384:	11012903          	lw	s2,272(sp)
}
80007388:	00078513          	mv	a0,a5
8000738c:	11c12083          	lw	ra,284(sp)
80007390:	11812403          	lw	s0,280(sp)
80007394:	12010113          	addi	sp,sp,288
80007398:	00008067          	ret

8000739c <sys_unlink>:
{
8000739c:	f2010113          	addi	sp,sp,-224
800073a0:	0c112e23          	sw	ra,220(sp)
800073a4:	0c812c23          	sw	s0,216(sp)
800073a8:	0e010413          	addi	s0,sp,224
  if(argstr(0, path, MAXPATH) < 0)
800073ac:	08000613          	li	a2,128
800073b0:	f4040593          	addi	a1,s0,-192
800073b4:	00000513          	li	a0,0
800073b8:	ffffc097          	auipc	ra,0xffffc
800073bc:	600080e7          	jalr	1536(ra) # 800039b8 <argstr>
800073c0:	20054863          	bltz	a0,800075d0 <sys_unlink+0x234>
800073c4:	0c912a23          	sw	s1,212(sp)
  begin_op();
800073c8:	ffffe097          	auipc	ra,0xffffe
800073cc:	2b0080e7          	jalr	688(ra) # 80005678 <begin_op>
  if((dp = nameiparent(path, name)) == 0){
800073d0:	fc040593          	addi	a1,s0,-64
800073d4:	f4040513          	addi	a0,s0,-192
800073d8:	ffffe097          	auipc	ra,0xffffe
800073dc:	00c080e7          	jalr	12(ra) # 800053e4 <nameiparent>
800073e0:	00050493          	mv	s1,a0
800073e4:	10050863          	beqz	a0,800074f4 <sys_unlink+0x158>
  ilock(dp);
800073e8:	ffffd097          	auipc	ra,0xffffd
800073ec:	4d0080e7          	jalr	1232(ra) # 800048b8 <ilock>
  if(namecmp(name, ".") == 0 || namecmp(name, "..") == 0)
800073f0:	00002597          	auipc	a1,0x2
800073f4:	2ec58593          	addi	a1,a1,748 # 800096dc <userret+0x63c>
800073f8:	fc040513          	addi	a0,s0,-64
800073fc:	ffffe097          	auipc	ra,0xffffe
80007400:	b2c080e7          	jalr	-1236(ra) # 80004f28 <namecmp>
80007404:	1a050063          	beqz	a0,800075a4 <sys_unlink+0x208>
80007408:	00002597          	auipc	a1,0x2
8000740c:	2d858593          	addi	a1,a1,728 # 800096e0 <userret+0x640>
80007410:	fc040513          	addi	a0,s0,-64
80007414:	ffffe097          	auipc	ra,0xffffe
80007418:	b14080e7          	jalr	-1260(ra) # 80004f28 <namecmp>
8000741c:	18050463          	beqz	a0,800075a4 <sys_unlink+0x208>
80007420:	0d212823          	sw	s2,208(sp)
  if((ip = dirlookup(dp, name, &off)) == 0)
80007424:	f3c40613          	addi	a2,s0,-196
80007428:	fc040593          	addi	a1,s0,-64
8000742c:	00048513          	mv	a0,s1
80007430:	ffffe097          	auipc	ra,0xffffe
80007434:	b24080e7          	jalr	-1244(ra) # 80004f54 <dirlookup>
80007438:	00050913          	mv	s2,a0
8000743c:	16050263          	beqz	a0,800075a0 <sys_unlink+0x204>
80007440:	0d312623          	sw	s3,204(sp)
  ilock(ip);
80007444:	ffffd097          	auipc	ra,0xffffd
80007448:	474080e7          	jalr	1140(ra) # 800048b8 <ilock>
  if(ip->nlink < 1)
8000744c:	02e91783          	lh	a5,46(s2)
80007450:	0af05c63          	blez	a5,80007508 <sys_unlink+0x16c>
  if(ip->type == T_DIR && !isdirempty(ip)){
80007454:	02891703          	lh	a4,40(s2)
80007458:	00100793          	li	a5,1
8000745c:	0af70e63          	beq	a4,a5,80007518 <sys_unlink+0x17c>
  memset(&de, 0, sizeof(de));
80007460:	fd040993          	addi	s3,s0,-48
80007464:	01000613          	li	a2,16
80007468:	00000593          	li	a1,0
8000746c:	00098513          	mv	a0,s3
80007470:	ffffa097          	auipc	ra,0xffffa
80007474:	b60080e7          	jalr	-1184(ra) # 80000fd0 <memset>
  if(writei(dp, 0, (uint32)&de, off, sizeof(de)) != sizeof(de))
80007478:	01000713          	li	a4,16
8000747c:	f3c42683          	lw	a3,-196(s0)
80007480:	00098613          	mv	a2,s3
80007484:	00000593          	li	a1,0
80007488:	00048513          	mv	a0,s1
8000748c:	ffffe097          	auipc	ra,0xffffe
80007490:	92c080e7          	jalr	-1748(ra) # 80004db8 <writei>
80007494:	01000793          	li	a5,16
80007498:	0cf51e63          	bne	a0,a5,80007574 <sys_unlink+0x1d8>
  if(ip->type == T_DIR){
8000749c:	02891703          	lh	a4,40(s2)
800074a0:	00100793          	li	a5,1
800074a4:	0ef70063          	beq	a4,a5,80007584 <sys_unlink+0x1e8>
  iunlockput(dp);
800074a8:	00048513          	mv	a0,s1
800074ac:	ffffd097          	auipc	ra,0xffffd
800074b0:	71c080e7          	jalr	1820(ra) # 80004bc8 <iunlockput>
  ip->nlink--;
800074b4:	02e95783          	lhu	a5,46(s2)
800074b8:	fff78793          	addi	a5,a5,-1
800074bc:	02f91723          	sh	a5,46(s2)
  iupdate(ip);
800074c0:	00090513          	mv	a0,s2
800074c4:	ffffd097          	auipc	ra,0xffffd
800074c8:	2d8080e7          	jalr	728(ra) # 8000479c <iupdate>
  iunlockput(ip);
800074cc:	00090513          	mv	a0,s2
800074d0:	ffffd097          	auipc	ra,0xffffd
800074d4:	6f8080e7          	jalr	1784(ra) # 80004bc8 <iunlockput>
  end_op();
800074d8:	ffffe097          	auipc	ra,0xffffe
800074dc:	254080e7          	jalr	596(ra) # 8000572c <end_op>
  return 0;
800074e0:	00000513          	li	a0,0
800074e4:	0d412483          	lw	s1,212(sp)
800074e8:	0d012903          	lw	s2,208(sp)
800074ec:	0cc12983          	lw	s3,204(sp)
800074f0:	0d00006f          	j	800075c0 <sys_unlink+0x224>
    end_op();
800074f4:	ffffe097          	auipc	ra,0xffffe
800074f8:	238080e7          	jalr	568(ra) # 8000572c <end_op>
    return -1;
800074fc:	fff00513          	li	a0,-1
80007500:	0d412483          	lw	s1,212(sp)
80007504:	0bc0006f          	j	800075c0 <sys_unlink+0x224>
    panic("unlink: nlink < 1");
80007508:	00002517          	auipc	a0,0x2
8000750c:	1f850513          	addi	a0,a0,504 # 80009700 <userret+0x660>
80007510:	ffff9097          	auipc	ra,0xffff9
80007514:	1ec080e7          	jalr	492(ra) # 800006fc <panic>
  for(off=2*sizeof(de); off<dp->size; off+=sizeof(de)){
80007518:	03092703          	lw	a4,48(s2)
8000751c:	02000793          	li	a5,32
80007520:	f4e7f0e3          	bgeu	a5,a4,80007460 <sys_unlink+0xc4>
80007524:	00078993          	mv	s3,a5
    if(readi(dp, 0, (uint32)&de, off, sizeof(de)) != sizeof(de))
80007528:	01000713          	li	a4,16
8000752c:	00098693          	mv	a3,s3
80007530:	f2c40613          	addi	a2,s0,-212
80007534:	00000593          	li	a1,0
80007538:	00090513          	mv	a0,s2
8000753c:	ffffd097          	auipc	ra,0xffffd
80007540:	718080e7          	jalr	1816(ra) # 80004c54 <readi>
80007544:	01000793          	li	a5,16
80007548:	00f51e63          	bne	a0,a5,80007564 <sys_unlink+0x1c8>
    if(de.inum != 0)
8000754c:	f2c45783          	lhu	a5,-212(s0)
80007550:	08079463          	bnez	a5,800075d8 <sys_unlink+0x23c>
  for(off=2*sizeof(de); off<dp->size; off+=sizeof(de)){
80007554:	01098993          	addi	s3,s3,16
80007558:	03092783          	lw	a5,48(s2)
8000755c:	fcf9e6e3          	bltu	s3,a5,80007528 <sys_unlink+0x18c>
80007560:	f01ff06f          	j	80007460 <sys_unlink+0xc4>
      panic("isdirempty: readi");
80007564:	00002517          	auipc	a0,0x2
80007568:	1b050513          	addi	a0,a0,432 # 80009714 <userret+0x674>
8000756c:	ffff9097          	auipc	ra,0xffff9
80007570:	190080e7          	jalr	400(ra) # 800006fc <panic>
    panic("unlink: writei");
80007574:	00002517          	auipc	a0,0x2
80007578:	1b450513          	addi	a0,a0,436 # 80009728 <userret+0x688>
8000757c:	ffff9097          	auipc	ra,0xffff9
80007580:	180080e7          	jalr	384(ra) # 800006fc <panic>
    dp->nlink--;
80007584:	02e4d783          	lhu	a5,46(s1)
80007588:	fff78793          	addi	a5,a5,-1
8000758c:	02f49723          	sh	a5,46(s1)
    iupdate(dp);
80007590:	00048513          	mv	a0,s1
80007594:	ffffd097          	auipc	ra,0xffffd
80007598:	208080e7          	jalr	520(ra) # 8000479c <iupdate>
8000759c:	f0dff06f          	j	800074a8 <sys_unlink+0x10c>
800075a0:	0d012903          	lw	s2,208(sp)
  iunlockput(dp);
800075a4:	00048513          	mv	a0,s1
800075a8:	ffffd097          	auipc	ra,0xffffd
800075ac:	620080e7          	jalr	1568(ra) # 80004bc8 <iunlockput>
  end_op();
800075b0:	ffffe097          	auipc	ra,0xffffe
800075b4:	17c080e7          	jalr	380(ra) # 8000572c <end_op>
  return -1;
800075b8:	fff00513          	li	a0,-1
800075bc:	0d412483          	lw	s1,212(sp)
}
800075c0:	0dc12083          	lw	ra,220(sp)
800075c4:	0d812403          	lw	s0,216(sp)
800075c8:	0e010113          	addi	sp,sp,224
800075cc:	00008067          	ret
    return -1;
800075d0:	fff00513          	li	a0,-1
800075d4:	fedff06f          	j	800075c0 <sys_unlink+0x224>
    iunlockput(ip);
800075d8:	00090513          	mv	a0,s2
800075dc:	ffffd097          	auipc	ra,0xffffd
800075e0:	5ec080e7          	jalr	1516(ra) # 80004bc8 <iunlockput>
    goto bad;
800075e4:	0d012903          	lw	s2,208(sp)
800075e8:	0cc12983          	lw	s3,204(sp)
800075ec:	fb9ff06f          	j	800075a4 <sys_unlink+0x208>

800075f0 <sys_open>:

uint32
sys_open(void)
{
800075f0:	f5010113          	addi	sp,sp,-176
800075f4:	0a112623          	sw	ra,172(sp)
800075f8:	0a812423          	sw	s0,168(sp)
800075fc:	0b010413          	addi	s0,sp,176
  int fd, omode;
  struct file *f;
  struct inode *ip;
  int n;

  if((n = argstr(0, path, MAXPATH)) < 0 || argint(1, &omode) < 0)
80007600:	08000613          	li	a2,128
80007604:	f6040593          	addi	a1,s0,-160
80007608:	00000513          	li	a0,0
8000760c:	ffffc097          	auipc	ra,0xffffc
80007610:	3ac080e7          	jalr	940(ra) # 800039b8 <argstr>
    return -1;
80007614:	fff00793          	li	a5,-1
  if((n = argstr(0, path, MAXPATH)) < 0 || argint(1, &omode) < 0)
80007618:	0e054863          	bltz	a0,80007708 <sys_open+0x118>
8000761c:	f5c40593          	addi	a1,s0,-164
80007620:	00100513          	li	a0,1
80007624:	ffffc097          	auipc	ra,0xffffc
80007628:	31c080e7          	jalr	796(ra) # 80003940 <argint>
    return -1;
8000762c:	fff00793          	li	a5,-1
  if((n = argstr(0, path, MAXPATH)) < 0 || argint(1, &omode) < 0)
80007630:	0c054c63          	bltz	a0,80007708 <sys_open+0x118>
80007634:	0a912223          	sw	s1,164(sp)

  begin_op();
80007638:	ffffe097          	auipc	ra,0xffffe
8000763c:	040080e7          	jalr	64(ra) # 80005678 <begin_op>

  if(omode & O_CREATE){
80007640:	f5c42783          	lw	a5,-164(s0)
80007644:	2007f793          	andi	a5,a5,512
80007648:	0e078463          	beqz	a5,80007730 <sys_open+0x140>
    ip = create(path, T_FILE, 0, 0);
8000764c:	00000693          	li	a3,0
80007650:	00000613          	li	a2,0
80007654:	00200593          	li	a1,2
80007658:	f6040513          	addi	a0,s0,-160
8000765c:	fffff097          	auipc	ra,0xfffff
80007660:	74c080e7          	jalr	1868(ra) # 80006da8 <create>
80007664:	00050493          	mv	s1,a0
    if(ip == 0){
80007668:	0a050a63          	beqz	a0,8000771c <sys_open+0x12c>
      end_op();
      return -1;
    }
  }

  if(ip->type == T_DEVICE && (ip->major < 0 || ip->major >= NDEV)){
8000766c:	02849703          	lh	a4,40(s1)
80007670:	00300793          	li	a5,3
80007674:	00f71863          	bne	a4,a5,80007684 <sys_open+0x94>
80007678:	02a4d703          	lhu	a4,42(s1)
8000767c:	00900793          	li	a5,9
80007680:	10e7ea63          	bltu	a5,a4,80007794 <sys_open+0x1a4>
80007684:	0b212023          	sw	s2,160(sp)
    iunlockput(ip);
    end_op();
    return -1;
  }

  if((f = filealloc()) == 0 || (fd = fdalloc(f)) < 0){
80007688:	ffffe097          	auipc	ra,0xffffe
8000768c:	590080e7          	jalr	1424(ra) # 80005c18 <filealloc>
80007690:	00050913          	mv	s2,a0
80007694:	12050863          	beqz	a0,800077c4 <sys_open+0x1d4>
80007698:	09312e23          	sw	s3,156(sp)
8000769c:	fffff097          	auipc	ra,0xfffff
800076a0:	69c080e7          	jalr	1692(ra) # 80006d38 <fdalloc>
800076a4:	00050993          	mv	s3,a0
800076a8:	10054663          	bltz	a0,800077b4 <sys_open+0x1c4>
    iunlockput(ip);
    end_op();
    return -1;
  }

  if(ip->type == T_DEVICE){
800076ac:	02849703          	lh	a4,40(s1)
800076b0:	00300793          	li	a5,3
800076b4:	12f70a63          	beq	a4,a5,800077e8 <sys_open+0x1f8>
    f->type = FD_DEVICE;
    f->major = ip->major;
  } else {
    f->type = FD_INODE;
800076b8:	00200793          	li	a5,2
800076bc:	00f92023          	sw	a5,0(s2)
    f->off = 0;
800076c0:	00092a23          	sw	zero,20(s2)
  }
  f->ip = ip;
800076c4:	00992823          	sw	s1,16(s2)
  f->readable = !(omode & O_WRONLY);
800076c8:	f5c42783          	lw	a5,-164(s0)
800076cc:	0017f713          	andi	a4,a5,1
800076d0:	00174713          	xori	a4,a4,1
800076d4:	00e90423          	sb	a4,8(s2)
  f->writable = (omode & O_WRONLY) || (omode & O_RDWR);
800076d8:	0037f793          	andi	a5,a5,3
800076dc:	00f037b3          	snez	a5,a5
800076e0:	00f904a3          	sb	a5,9(s2)

  iunlock(ip);
800076e4:	00048513          	mv	a0,s1
800076e8:	ffffd097          	auipc	ra,0xffffd
800076ec:	2dc080e7          	jalr	732(ra) # 800049c4 <iunlock>
  end_op();
800076f0:	ffffe097          	auipc	ra,0xffffe
800076f4:	03c080e7          	jalr	60(ra) # 8000572c <end_op>

  return fd;
800076f8:	00098793          	mv	a5,s3
800076fc:	0a412483          	lw	s1,164(sp)
80007700:	0a012903          	lw	s2,160(sp)
80007704:	09c12983          	lw	s3,156(sp)
}
80007708:	00078513          	mv	a0,a5
8000770c:	0ac12083          	lw	ra,172(sp)
80007710:	0a812403          	lw	s0,168(sp)
80007714:	0b010113          	addi	sp,sp,176
80007718:	00008067          	ret
      end_op();
8000771c:	ffffe097          	auipc	ra,0xffffe
80007720:	010080e7          	jalr	16(ra) # 8000572c <end_op>
      return -1;
80007724:	fff00793          	li	a5,-1
80007728:	0a412483          	lw	s1,164(sp)
8000772c:	fddff06f          	j	80007708 <sys_open+0x118>
    if((ip = namei(path)) == 0){
80007730:	f6040513          	addi	a0,s0,-160
80007734:	ffffe097          	auipc	ra,0xffffe
80007738:	c80080e7          	jalr	-896(ra) # 800053b4 <namei>
8000773c:	00050493          	mv	s1,a0
80007740:	04050063          	beqz	a0,80007780 <sys_open+0x190>
    ilock(ip);
80007744:	ffffd097          	auipc	ra,0xffffd
80007748:	174080e7          	jalr	372(ra) # 800048b8 <ilock>
    if(ip->type == T_DIR && omode != O_RDONLY){
8000774c:	02849703          	lh	a4,40(s1)
80007750:	00100793          	li	a5,1
80007754:	f0f71ce3          	bne	a4,a5,8000766c <sys_open+0x7c>
80007758:	f5c42783          	lw	a5,-164(s0)
8000775c:	f20784e3          	beqz	a5,80007684 <sys_open+0x94>
      iunlockput(ip);
80007760:	00048513          	mv	a0,s1
80007764:	ffffd097          	auipc	ra,0xffffd
80007768:	464080e7          	jalr	1124(ra) # 80004bc8 <iunlockput>
      end_op();
8000776c:	ffffe097          	auipc	ra,0xffffe
80007770:	fc0080e7          	jalr	-64(ra) # 8000572c <end_op>
      return -1;
80007774:	fff00793          	li	a5,-1
80007778:	0a412483          	lw	s1,164(sp)
8000777c:	f8dff06f          	j	80007708 <sys_open+0x118>
      end_op();
80007780:	ffffe097          	auipc	ra,0xffffe
80007784:	fac080e7          	jalr	-84(ra) # 8000572c <end_op>
      return -1;
80007788:	fff00793          	li	a5,-1
8000778c:	0a412483          	lw	s1,164(sp)
80007790:	f79ff06f          	j	80007708 <sys_open+0x118>
    iunlockput(ip);
80007794:	00048513          	mv	a0,s1
80007798:	ffffd097          	auipc	ra,0xffffd
8000779c:	430080e7          	jalr	1072(ra) # 80004bc8 <iunlockput>
    end_op();
800077a0:	ffffe097          	auipc	ra,0xffffe
800077a4:	f8c080e7          	jalr	-116(ra) # 8000572c <end_op>
    return -1;
800077a8:	fff00793          	li	a5,-1
800077ac:	0a412483          	lw	s1,164(sp)
800077b0:	f59ff06f          	j	80007708 <sys_open+0x118>
      fileclose(f);
800077b4:	00090513          	mv	a0,s2
800077b8:	ffffe097          	auipc	ra,0xffffe
800077bc:	55c080e7          	jalr	1372(ra) # 80005d14 <fileclose>
800077c0:	09c12983          	lw	s3,156(sp)
    iunlockput(ip);
800077c4:	00048513          	mv	a0,s1
800077c8:	ffffd097          	auipc	ra,0xffffd
800077cc:	400080e7          	jalr	1024(ra) # 80004bc8 <iunlockput>
    end_op();
800077d0:	ffffe097          	auipc	ra,0xffffe
800077d4:	f5c080e7          	jalr	-164(ra) # 8000572c <end_op>
    return -1;
800077d8:	fff00793          	li	a5,-1
800077dc:	0a412483          	lw	s1,164(sp)
800077e0:	0a012903          	lw	s2,160(sp)
800077e4:	f25ff06f          	j	80007708 <sys_open+0x118>
    f->type = FD_DEVICE;
800077e8:	00e92023          	sw	a4,0(s2)
    f->major = ip->major;
800077ec:	02a49783          	lh	a5,42(s1)
800077f0:	00f91c23          	sh	a5,24(s2)
800077f4:	ed1ff06f          	j	800076c4 <sys_open+0xd4>

800077f8 <sys_mkdir>:

uint32
sys_mkdir(void)
{
800077f8:	f7010113          	addi	sp,sp,-144
800077fc:	08112623          	sw	ra,140(sp)
80007800:	08812423          	sw	s0,136(sp)
80007804:	09010413          	addi	s0,sp,144
  char path[MAXPATH];
  struct inode *ip;

  begin_op();
80007808:	ffffe097          	auipc	ra,0xffffe
8000780c:	e70080e7          	jalr	-400(ra) # 80005678 <begin_op>
  if(argstr(0, path, MAXPATH) < 0 || (ip = create(path, T_DIR, 0, 0)) == 0){
80007810:	08000613          	li	a2,128
80007814:	f7040593          	addi	a1,s0,-144
80007818:	00000513          	li	a0,0
8000781c:	ffffc097          	auipc	ra,0xffffc
80007820:	19c080e7          	jalr	412(ra) # 800039b8 <argstr>
80007824:	04054263          	bltz	a0,80007868 <sys_mkdir+0x70>
80007828:	00000693          	li	a3,0
8000782c:	00000613          	li	a2,0
80007830:	00100593          	li	a1,1
80007834:	f7040513          	addi	a0,s0,-144
80007838:	fffff097          	auipc	ra,0xfffff
8000783c:	570080e7          	jalr	1392(ra) # 80006da8 <create>
80007840:	02050463          	beqz	a0,80007868 <sys_mkdir+0x70>
    end_op();
    return -1;
  }
  iunlockput(ip);
80007844:	ffffd097          	auipc	ra,0xffffd
80007848:	384080e7          	jalr	900(ra) # 80004bc8 <iunlockput>
  end_op();
8000784c:	ffffe097          	auipc	ra,0xffffe
80007850:	ee0080e7          	jalr	-288(ra) # 8000572c <end_op>
  return 0;
80007854:	00000513          	li	a0,0
}
80007858:	08c12083          	lw	ra,140(sp)
8000785c:	08812403          	lw	s0,136(sp)
80007860:	09010113          	addi	sp,sp,144
80007864:	00008067          	ret
    end_op();
80007868:	ffffe097          	auipc	ra,0xffffe
8000786c:	ec4080e7          	jalr	-316(ra) # 8000572c <end_op>
    return -1;
80007870:	fff00513          	li	a0,-1
80007874:	fe5ff06f          	j	80007858 <sys_mkdir+0x60>

80007878 <sys_mknod>:

uint32
sys_mknod(void)
{
80007878:	f6010113          	addi	sp,sp,-160
8000787c:	08112e23          	sw	ra,156(sp)
80007880:	08812c23          	sw	s0,152(sp)
80007884:	0a010413          	addi	s0,sp,160
  struct inode *ip;
  char path[MAXPATH];
  int major, minor;

  begin_op();
80007888:	ffffe097          	auipc	ra,0xffffe
8000788c:	df0080e7          	jalr	-528(ra) # 80005678 <begin_op>
  if((argstr(0, path, MAXPATH)) < 0 ||
80007890:	08000613          	li	a2,128
80007894:	f7040593          	addi	a1,s0,-144
80007898:	00000513          	li	a0,0
8000789c:	ffffc097          	auipc	ra,0xffffc
800078a0:	11c080e7          	jalr	284(ra) # 800039b8 <argstr>
800078a4:	06054063          	bltz	a0,80007904 <sys_mknod+0x8c>
     argint(1, &major) < 0 ||
800078a8:	f6c40593          	addi	a1,s0,-148
800078ac:	00100513          	li	a0,1
800078b0:	ffffc097          	auipc	ra,0xffffc
800078b4:	090080e7          	jalr	144(ra) # 80003940 <argint>
  if((argstr(0, path, MAXPATH)) < 0 ||
800078b8:	04054663          	bltz	a0,80007904 <sys_mknod+0x8c>
     argint(2, &minor) < 0 ||
800078bc:	f6840593          	addi	a1,s0,-152
800078c0:	00200513          	li	a0,2
800078c4:	ffffc097          	auipc	ra,0xffffc
800078c8:	07c080e7          	jalr	124(ra) # 80003940 <argint>
     argint(1, &major) < 0 ||
800078cc:	02054c63          	bltz	a0,80007904 <sys_mknod+0x8c>
     (ip = create(path, T_DEVICE, major, minor)) == 0){
800078d0:	f6841683          	lh	a3,-152(s0)
800078d4:	f6c41603          	lh	a2,-148(s0)
800078d8:	00300593          	li	a1,3
800078dc:	f7040513          	addi	a0,s0,-144
800078e0:	fffff097          	auipc	ra,0xfffff
800078e4:	4c8080e7          	jalr	1224(ra) # 80006da8 <create>
     argint(2, &minor) < 0 ||
800078e8:	00050e63          	beqz	a0,80007904 <sys_mknod+0x8c>
    end_op();
    return -1;
  }
  iunlockput(ip);
800078ec:	ffffd097          	auipc	ra,0xffffd
800078f0:	2dc080e7          	jalr	732(ra) # 80004bc8 <iunlockput>
  end_op();
800078f4:	ffffe097          	auipc	ra,0xffffe
800078f8:	e38080e7          	jalr	-456(ra) # 8000572c <end_op>
  return 0;
800078fc:	00000513          	li	a0,0
80007900:	0100006f          	j	80007910 <sys_mknod+0x98>
    end_op();
80007904:	ffffe097          	auipc	ra,0xffffe
80007908:	e28080e7          	jalr	-472(ra) # 8000572c <end_op>
    return -1;
8000790c:	fff00513          	li	a0,-1
}
80007910:	09c12083          	lw	ra,156(sp)
80007914:	09812403          	lw	s0,152(sp)
80007918:	0a010113          	addi	sp,sp,160
8000791c:	00008067          	ret

80007920 <sys_chdir>:

uint32
sys_chdir(void)
{
80007920:	f7010113          	addi	sp,sp,-144
80007924:	08112623          	sw	ra,140(sp)
80007928:	08812423          	sw	s0,136(sp)
8000792c:	09212023          	sw	s2,128(sp)
80007930:	09010413          	addi	s0,sp,144
  char path[MAXPATH];
  struct inode *ip;
  struct proc *p = myproc();
80007934:	ffffb097          	auipc	ra,0xffffb
80007938:	9a8080e7          	jalr	-1624(ra) # 800022dc <myproc>
8000793c:	00050913          	mv	s2,a0
  
  begin_op();
80007940:	ffffe097          	auipc	ra,0xffffe
80007944:	d38080e7          	jalr	-712(ra) # 80005678 <begin_op>
  if(argstr(0, path, MAXPATH) < 0 || (ip = namei(path)) == 0){
80007948:	08000613          	li	a2,128
8000794c:	f7040593          	addi	a1,s0,-144
80007950:	00000513          	li	a0,0
80007954:	ffffc097          	auipc	ra,0xffffc
80007958:	064080e7          	jalr	100(ra) # 800039b8 <argstr>
8000795c:	06054a63          	bltz	a0,800079d0 <sys_chdir+0xb0>
80007960:	08912223          	sw	s1,132(sp)
80007964:	f7040513          	addi	a0,s0,-144
80007968:	ffffe097          	auipc	ra,0xffffe
8000796c:	a4c080e7          	jalr	-1460(ra) # 800053b4 <namei>
80007970:	00050493          	mv	s1,a0
80007974:	04050c63          	beqz	a0,800079cc <sys_chdir+0xac>
    end_op();
    return -1;
  }
  ilock(ip);
80007978:	ffffd097          	auipc	ra,0xffffd
8000797c:	f40080e7          	jalr	-192(ra) # 800048b8 <ilock>
  if(ip->type != T_DIR){
80007980:	02849703          	lh	a4,40(s1)
80007984:	00100793          	li	a5,1
80007988:	04f71c63          	bne	a4,a5,800079e0 <sys_chdir+0xc0>
    iunlockput(ip);
    end_op();
    return -1;
  }
  iunlock(ip);
8000798c:	00048513          	mv	a0,s1
80007990:	ffffd097          	auipc	ra,0xffffd
80007994:	034080e7          	jalr	52(ra) # 800049c4 <iunlock>
  iput(p->cwd);
80007998:	0ac92503          	lw	a0,172(s2)
8000799c:	ffffd097          	auipc	ra,0xffffd
800079a0:	098080e7          	jalr	152(ra) # 80004a34 <iput>
  end_op();
800079a4:	ffffe097          	auipc	ra,0xffffe
800079a8:	d88080e7          	jalr	-632(ra) # 8000572c <end_op>
  p->cwd = ip;
800079ac:	0a992623          	sw	s1,172(s2)
  return 0;
800079b0:	00000513          	li	a0,0
800079b4:	08412483          	lw	s1,132(sp)
}
800079b8:	08c12083          	lw	ra,140(sp)
800079bc:	08812403          	lw	s0,136(sp)
800079c0:	08012903          	lw	s2,128(sp)
800079c4:	09010113          	addi	sp,sp,144
800079c8:	00008067          	ret
800079cc:	08412483          	lw	s1,132(sp)
    end_op();
800079d0:	ffffe097          	auipc	ra,0xffffe
800079d4:	d5c080e7          	jalr	-676(ra) # 8000572c <end_op>
    return -1;
800079d8:	fff00513          	li	a0,-1
800079dc:	fddff06f          	j	800079b8 <sys_chdir+0x98>
    iunlockput(ip);
800079e0:	00048513          	mv	a0,s1
800079e4:	ffffd097          	auipc	ra,0xffffd
800079e8:	1e4080e7          	jalr	484(ra) # 80004bc8 <iunlockput>
    end_op();
800079ec:	ffffe097          	auipc	ra,0xffffe
800079f0:	d40080e7          	jalr	-704(ra) # 8000572c <end_op>
    return -1;
800079f4:	fff00513          	li	a0,-1
800079f8:	08412483          	lw	s1,132(sp)
800079fc:	fbdff06f          	j	800079b8 <sys_chdir+0x98>

80007a00 <sys_exec>:

uint32
sys_exec(void)
{
80007a00:	ed010113          	addi	sp,sp,-304
80007a04:	12112623          	sw	ra,300(sp)
80007a08:	12812423          	sw	s0,296(sp)
80007a0c:	13010413          	addi	s0,sp,304
  char path[MAXPATH], *argv[MAXARG];
  int i;
  uint32 uargv, uarg;

  if(argstr(0, path, MAXPATH) < 0 || argaddr(1, &uargv) < 0){
80007a10:	08000613          	li	a2,128
80007a14:	f6040593          	addi	a1,s0,-160
80007a18:	00000513          	li	a0,0
80007a1c:	ffffc097          	auipc	ra,0xffffc
80007a20:	f9c080e7          	jalr	-100(ra) # 800039b8 <argstr>
80007a24:	16054e63          	bltz	a0,80007ba0 <sys_exec+0x1a0>
80007a28:	edc40593          	addi	a1,s0,-292
80007a2c:	00100513          	li	a0,1
80007a30:	ffffc097          	auipc	ra,0xffffc
80007a34:	f4c080e7          	jalr	-180(ra) # 8000397c <argaddr>
80007a38:	16054e63          	bltz	a0,80007bb4 <sys_exec+0x1b4>
80007a3c:	12912223          	sw	s1,292(sp)
80007a40:	13212023          	sw	s2,288(sp)
80007a44:	11312e23          	sw	s3,284(sp)
80007a48:	11412c23          	sw	s4,280(sp)
80007a4c:	11512a23          	sw	s5,276(sp)
80007a50:	11612823          	sw	s6,272(sp)
    return -1;
  }

  memset(argv, 0, sizeof(argv));
80007a54:	08000613          	li	a2,128
80007a58:	00000593          	li	a1,0
80007a5c:	ee040513          	addi	a0,s0,-288
80007a60:	ffff9097          	auipc	ra,0xffff9
80007a64:	570080e7          	jalr	1392(ra) # 80000fd0 <memset>
  for(i=0;; i++){
    if(i >= NELEM(argv)){
80007a68:	ee040493          	addi	s1,s0,-288
  memset(argv, 0, sizeof(argv));
80007a6c:	00048993          	mv	s3,s1
  for(i=0;; i++){
80007a70:	00000913          	li	s2,0
      goto bad;
    }
    if(fetchaddr(uargv+sizeof(uint32)*i, (uint32*)&uarg) < 0){
80007a74:	ed840a13          	addi	s4,s0,-296
      break;
    }
    argv[i] = kalloc();
    if(argv[i] == 0)
      panic("sys_exec kalloc");
    if(fetchstr(uarg, argv[i], PGSIZE) < 0){
80007a78:	00001ab7          	lui	s5,0x1
    if(i >= NELEM(argv)){
80007a7c:	02000b13          	li	s6,32
    if(fetchaddr(uargv+sizeof(uint32)*i, (uint32*)&uarg) < 0){
80007a80:	00291513          	slli	a0,s2,0x2
80007a84:	000a0593          	mv	a1,s4
80007a88:	edc42783          	lw	a5,-292(s0)
80007a8c:	00f50533          	add	a0,a0,a5
80007a90:	ffffc097          	auipc	ra,0xffffc
80007a94:	dbc080e7          	jalr	-580(ra) # 8000384c <fetchaddr>
80007a98:	04054063          	bltz	a0,80007ad8 <sys_exec+0xd8>
    if(uarg == 0){
80007a9c:	ed842783          	lw	a5,-296(s0)
80007aa0:	06078a63          	beqz	a5,80007b14 <sys_exec+0x114>
    argv[i] = kalloc();
80007aa4:	ffff9097          	auipc	ra,0xffff9
80007aa8:	23c080e7          	jalr	572(ra) # 80000ce0 <kalloc>
80007aac:	00050593          	mv	a1,a0
80007ab0:	00a9a023          	sw	a0,0(s3)
    if(argv[i] == 0)
80007ab4:	0a050e63          	beqz	a0,80007b70 <sys_exec+0x170>
    if(fetchstr(uarg, argv[i], PGSIZE) < 0){
80007ab8:	000a8613          	mv	a2,s5
80007abc:	ed842503          	lw	a0,-296(s0)
80007ac0:	ffffc097          	auipc	ra,0xffffc
80007ac4:	e0c080e7          	jalr	-500(ra) # 800038cc <fetchstr>
80007ac8:	00054863          	bltz	a0,80007ad8 <sys_exec+0xd8>
  for(i=0;; i++){
80007acc:	00190913          	addi	s2,s2,1
    if(i >= NELEM(argv)){
80007ad0:	00498993          	addi	s3,s3,4
80007ad4:	fb6916e3          	bne	s2,s6,80007a80 <sys_exec+0x80>
    kfree(argv[i]);

  return ret;

 bad:
  for(i = 0; i < NELEM(argv) && argv[i] != 0; i++)
80007ad8:	f6040913          	addi	s2,s0,-160
80007adc:	0004a503          	lw	a0,0(s1)
80007ae0:	0a050063          	beqz	a0,80007b80 <sys_exec+0x180>
    kfree(argv[i]);
80007ae4:	ffff9097          	auipc	ra,0xffff9
80007ae8:	08c080e7          	jalr	140(ra) # 80000b70 <kfree>
  for(i = 0; i < NELEM(argv) && argv[i] != 0; i++)
80007aec:	00448493          	addi	s1,s1,4
80007af0:	ff2496e3          	bne	s1,s2,80007adc <sys_exec+0xdc>
  return -1;
80007af4:	fff00513          	li	a0,-1
80007af8:	12412483          	lw	s1,292(sp)
80007afc:	12012903          	lw	s2,288(sp)
80007b00:	11c12983          	lw	s3,284(sp)
80007b04:	11812a03          	lw	s4,280(sp)
80007b08:	11412a83          	lw	s5,276(sp)
80007b0c:	11012b03          	lw	s6,272(sp)
80007b10:	0940006f          	j	80007ba4 <sys_exec+0x1a4>
      argv[i] = 0;
80007b14:	ee040593          	addi	a1,s0,-288
80007b18:	00291913          	slli	s2,s2,0x2
80007b1c:	00b90933          	add	s2,s2,a1
80007b20:	00092023          	sw	zero,0(s2)
  int ret = exec(path, argv);
80007b24:	f6040513          	addi	a0,s0,-160
80007b28:	fffff097          	auipc	ra,0xfffff
80007b2c:	bf4080e7          	jalr	-1036(ra) # 8000671c <exec>
80007b30:	00050913          	mv	s2,a0
  for(i = 0; i < NELEM(argv) && argv[i] != 0; i++)
80007b34:	f6040993          	addi	s3,s0,-160
80007b38:	0004a503          	lw	a0,0(s1)
80007b3c:	00050a63          	beqz	a0,80007b50 <sys_exec+0x150>
    kfree(argv[i]);
80007b40:	ffff9097          	auipc	ra,0xffff9
80007b44:	030080e7          	jalr	48(ra) # 80000b70 <kfree>
  for(i = 0; i < NELEM(argv) && argv[i] != 0; i++)
80007b48:	00448493          	addi	s1,s1,4
80007b4c:	ff3496e3          	bne	s1,s3,80007b38 <sys_exec+0x138>
  return ret;
80007b50:	00090513          	mv	a0,s2
80007b54:	12412483          	lw	s1,292(sp)
80007b58:	12012903          	lw	s2,288(sp)
80007b5c:	11c12983          	lw	s3,284(sp)
80007b60:	11812a03          	lw	s4,280(sp)
80007b64:	11412a83          	lw	s5,276(sp)
80007b68:	11012b03          	lw	s6,272(sp)
80007b6c:	0380006f          	j	80007ba4 <sys_exec+0x1a4>
      panic("sys_exec kalloc");
80007b70:	00002517          	auipc	a0,0x2
80007b74:	bc850513          	addi	a0,a0,-1080 # 80009738 <userret+0x698>
80007b78:	ffff9097          	auipc	ra,0xffff9
80007b7c:	b84080e7          	jalr	-1148(ra) # 800006fc <panic>
  return -1;
80007b80:	fff00513          	li	a0,-1
80007b84:	12412483          	lw	s1,292(sp)
80007b88:	12012903          	lw	s2,288(sp)
80007b8c:	11c12983          	lw	s3,284(sp)
80007b90:	11812a03          	lw	s4,280(sp)
80007b94:	11412a83          	lw	s5,276(sp)
80007b98:	11012b03          	lw	s6,272(sp)
80007b9c:	0080006f          	j	80007ba4 <sys_exec+0x1a4>
    return -1;
80007ba0:	fff00513          	li	a0,-1
}
80007ba4:	12c12083          	lw	ra,300(sp)
80007ba8:	12812403          	lw	s0,296(sp)
80007bac:	13010113          	addi	sp,sp,304
80007bb0:	00008067          	ret
    return -1;
80007bb4:	fff00513          	li	a0,-1
80007bb8:	fedff06f          	j	80007ba4 <sys_exec+0x1a4>

80007bbc <sys_pipe>:

uint32
sys_pipe(void)
{
80007bbc:	fd010113          	addi	sp,sp,-48
80007bc0:	02112623          	sw	ra,44(sp)
80007bc4:	02812423          	sw	s0,40(sp)
80007bc8:	02912223          	sw	s1,36(sp)
80007bcc:	03010413          	addi	s0,sp,48
  uint32 fdarray; // user pointer to array of two integers
  struct file *rf, *wf;
  int fd0, fd1;
  struct proc *p = myproc();
80007bd0:	ffffa097          	auipc	ra,0xffffa
80007bd4:	70c080e7          	jalr	1804(ra) # 800022dc <myproc>
80007bd8:	00050493          	mv	s1,a0

  if(argaddr(0, &fdarray) < 0)
80007bdc:	fec40593          	addi	a1,s0,-20
80007be0:	00000513          	li	a0,0
80007be4:	ffffc097          	auipc	ra,0xffffc
80007be8:	d98080e7          	jalr	-616(ra) # 8000397c <argaddr>
    return -1;
80007bec:	fff00793          	li	a5,-1
  if(argaddr(0, &fdarray) < 0)
80007bf0:	10054263          	bltz	a0,80007cf4 <sys_pipe+0x138>
  if(pipealloc(&rf, &wf) < 0)
80007bf4:	fe440593          	addi	a1,s0,-28
80007bf8:	fe840513          	addi	a0,s0,-24
80007bfc:	ffffe097          	auipc	ra,0xffffe
80007c00:	660080e7          	jalr	1632(ra) # 8000625c <pipealloc>
    return -1;
80007c04:	fff00793          	li	a5,-1
  if(pipealloc(&rf, &wf) < 0)
80007c08:	0e054663          	bltz	a0,80007cf4 <sys_pipe+0x138>
  fd0 = -1;
80007c0c:	fef42023          	sw	a5,-32(s0)
  if((fd0 = fdalloc(rf)) < 0 || (fd1 = fdalloc(wf)) < 0){
80007c10:	fe842503          	lw	a0,-24(s0)
80007c14:	fffff097          	auipc	ra,0xfffff
80007c18:	124080e7          	jalr	292(ra) # 80006d38 <fdalloc>
80007c1c:	fea42023          	sw	a0,-32(s0)
80007c20:	0a054c63          	bltz	a0,80007cd8 <sys_pipe+0x11c>
80007c24:	fe442503          	lw	a0,-28(s0)
80007c28:	fffff097          	auipc	ra,0xfffff
80007c2c:	110080e7          	jalr	272(ra) # 80006d38 <fdalloc>
80007c30:	fca42e23          	sw	a0,-36(s0)
80007c34:	08054663          	bltz	a0,80007cc0 <sys_pipe+0x104>
      p->ofile[fd0] = 0;
    fileclose(rf);
    fileclose(wf);
    return -1;
  }
  if(copyout(p->pagetable, fdarray, (char*)&fd0, sizeof(fd0)) < 0 ||
80007c38:	00400693          	li	a3,4
80007c3c:	fe040613          	addi	a2,s0,-32
80007c40:	fec42583          	lw	a1,-20(s0)
80007c44:	02c4a503          	lw	a0,44(s1)
80007c48:	ffffa097          	auipc	ra,0xffffa
80007c4c:	1b4080e7          	jalr	436(ra) # 80001dfc <copyout>
80007c50:	02054463          	bltz	a0,80007c78 <sys_pipe+0xbc>
     copyout(p->pagetable, fdarray+sizeof(fd0), (char *)&fd1, sizeof(fd1)) < 0){
80007c54:	00400693          	li	a3,4
80007c58:	fdc40613          	addi	a2,s0,-36
80007c5c:	fec42583          	lw	a1,-20(s0)
80007c60:	00d585b3          	add	a1,a1,a3
80007c64:	02c4a503          	lw	a0,44(s1)
80007c68:	ffffa097          	auipc	ra,0xffffa
80007c6c:	194080e7          	jalr	404(ra) # 80001dfc <copyout>
    p->ofile[fd1] = 0;
    fileclose(rf);
    fileclose(wf);
    return -1;
  }
  return 0;
80007c70:	00000793          	li	a5,0
  if(copyout(p->pagetable, fdarray, (char*)&fd0, sizeof(fd0)) < 0 ||
80007c74:	08055063          	bgez	a0,80007cf4 <sys_pipe+0x138>
    p->ofile[fd0] = 0;
80007c78:	fe042783          	lw	a5,-32(s0)
80007c7c:	01878793          	addi	a5,a5,24
80007c80:	00279793          	slli	a5,a5,0x2
80007c84:	00f487b3          	add	a5,s1,a5
80007c88:	0007a623          	sw	zero,12(a5)
    p->ofile[fd1] = 0;
80007c8c:	fdc42783          	lw	a5,-36(s0)
80007c90:	01878793          	addi	a5,a5,24
80007c94:	00279793          	slli	a5,a5,0x2
80007c98:	00f48533          	add	a0,s1,a5
80007c9c:	00052623          	sw	zero,12(a0)
    fileclose(rf);
80007ca0:	fe842503          	lw	a0,-24(s0)
80007ca4:	ffffe097          	auipc	ra,0xffffe
80007ca8:	070080e7          	jalr	112(ra) # 80005d14 <fileclose>
    fileclose(wf);
80007cac:	fe442503          	lw	a0,-28(s0)
80007cb0:	ffffe097          	auipc	ra,0xffffe
80007cb4:	064080e7          	jalr	100(ra) # 80005d14 <fileclose>
    return -1;
80007cb8:	fff00793          	li	a5,-1
80007cbc:	0380006f          	j	80007cf4 <sys_pipe+0x138>
    if(fd0 >= 0)
80007cc0:	fe042783          	lw	a5,-32(s0)
80007cc4:	0007ca63          	bltz	a5,80007cd8 <sys_pipe+0x11c>
      p->ofile[fd0] = 0;
80007cc8:	01878793          	addi	a5,a5,24
80007ccc:	00279793          	slli	a5,a5,0x2
80007cd0:	00f487b3          	add	a5,s1,a5
80007cd4:	0007a623          	sw	zero,12(a5)
    fileclose(rf);
80007cd8:	fe842503          	lw	a0,-24(s0)
80007cdc:	ffffe097          	auipc	ra,0xffffe
80007ce0:	038080e7          	jalr	56(ra) # 80005d14 <fileclose>
    fileclose(wf);
80007ce4:	fe442503          	lw	a0,-28(s0)
80007ce8:	ffffe097          	auipc	ra,0xffffe
80007cec:	02c080e7          	jalr	44(ra) # 80005d14 <fileclose>
    return -1;
80007cf0:	fff00793          	li	a5,-1
}
80007cf4:	00078513          	mv	a0,a5
80007cf8:	02c12083          	lw	ra,44(sp)
80007cfc:	02812403          	lw	s0,40(sp)
80007d00:	02412483          	lw	s1,36(sp)
80007d04:	03010113          	addi	sp,sp,48
80007d08:	00008067          	ret
80007d0c:	0000                	.insn	2, 0x0000
	...

80007d10 <kernelvec>:
80007d10:	f8010113          	addi	sp,sp,-128
80007d14:	00112023          	sw	ra,0(sp)
80007d18:	00212223          	sw	sp,4(sp)
80007d1c:	00312423          	sw	gp,8(sp)
80007d20:	00412623          	sw	tp,12(sp)
80007d24:	00512823          	sw	t0,16(sp)
80007d28:	00612a23          	sw	t1,20(sp)
80007d2c:	00712c23          	sw	t2,24(sp)
80007d30:	00812e23          	sw	s0,28(sp)
80007d34:	02912023          	sw	s1,32(sp)
80007d38:	02a12223          	sw	a0,36(sp)
80007d3c:	02b12423          	sw	a1,40(sp)
80007d40:	02c12623          	sw	a2,44(sp)
80007d44:	02d12823          	sw	a3,48(sp)
80007d48:	02e12a23          	sw	a4,52(sp)
80007d4c:	02f12c23          	sw	a5,56(sp)
80007d50:	03012e23          	sw	a6,60(sp)
80007d54:	05112023          	sw	a7,64(sp)
80007d58:	05212223          	sw	s2,68(sp)
80007d5c:	05312423          	sw	s3,72(sp)
80007d60:	05412623          	sw	s4,76(sp)
80007d64:	05512823          	sw	s5,80(sp)
80007d68:	05612a23          	sw	s6,84(sp)
80007d6c:	05712c23          	sw	s7,88(sp)
80007d70:	05812e23          	sw	s8,92(sp)
80007d74:	07912023          	sw	s9,96(sp)
80007d78:	07a12223          	sw	s10,100(sp)
80007d7c:	07b12423          	sw	s11,104(sp)
80007d80:	07c12623          	sw	t3,108(sp)
80007d84:	07d12823          	sw	t4,112(sp)
80007d88:	07e12a23          	sw	t5,116(sp)
80007d8c:	07f12c23          	sw	t6,120(sp)
80007d90:	911fb0ef          	jal	800036a0 <kerneltrap>
80007d94:	00012083          	lw	ra,0(sp)
80007d98:	00412103          	lw	sp,4(sp)
80007d9c:	00812183          	lw	gp,8(sp)
80007da0:	01012283          	lw	t0,16(sp)
80007da4:	01412303          	lw	t1,20(sp)
80007da8:	01812383          	lw	t2,24(sp)
80007dac:	01c12403          	lw	s0,28(sp)
80007db0:	02012483          	lw	s1,32(sp)
80007db4:	02412503          	lw	a0,36(sp)
80007db8:	02812583          	lw	a1,40(sp)
80007dbc:	02c12603          	lw	a2,44(sp)
80007dc0:	03012683          	lw	a3,48(sp)
80007dc4:	03412703          	lw	a4,52(sp)
80007dc8:	03812783          	lw	a5,56(sp)
80007dcc:	03c12803          	lw	a6,60(sp)
80007dd0:	04012883          	lw	a7,64(sp)
80007dd4:	04412903          	lw	s2,68(sp)
80007dd8:	04812983          	lw	s3,72(sp)
80007ddc:	04c12a03          	lw	s4,76(sp)
80007de0:	05012a83          	lw	s5,80(sp)
80007de4:	05412b03          	lw	s6,84(sp)
80007de8:	05812b83          	lw	s7,88(sp)
80007dec:	05c12c03          	lw	s8,92(sp)
80007df0:	06012c83          	lw	s9,96(sp)
80007df4:	06412d03          	lw	s10,100(sp)
80007df8:	06812d83          	lw	s11,104(sp)
80007dfc:	06c12e03          	lw	t3,108(sp)
80007e00:	07012e83          	lw	t4,112(sp)
80007e04:	07412f03          	lw	t5,116(sp)
80007e08:	07812f83          	lw	t6,120(sp)
80007e0c:	08010113          	addi	sp,sp,128
80007e10:	10200073          	sret
80007e14:	00000013          	nop
80007e18:	00000013          	nop
80007e1c:	00000013          	nop

80007e20 <timervec>:
80007e20:	34051573          	csrrw	a0,mscratch,a0
80007e24:	00b52023          	sw	a1,0(a0)
80007e28:	00c52223          	sw	a2,4(a0)
80007e2c:	00d52423          	sw	a3,8(a0)
80007e30:	00e52623          	sw	a4,12(a0)
80007e34:	01052583          	lw	a1,16(a0)
80007e38:	01452603          	lw	a2,20(a0)
80007e3c:	0005a683          	lw	a3,0(a1)
80007e40:	0045a703          	lw	a4,4(a1)
80007e44:	00c686b3          	add	a3,a3,a2
80007e48:	00c6b633          	sltu	a2,a3,a2
80007e4c:	00c70733          	add	a4,a4,a2
80007e50:	fff00613          	li	a2,-1
80007e54:	00c5a023          	sw	a2,0(a1)
80007e58:	00e5a223          	sw	a4,4(a1)
80007e5c:	00d5a023          	sw	a3,0(a1)
80007e60:	00200593          	li	a1,2
80007e64:	14459073          	csrw	sip,a1
80007e68:	00c52703          	lw	a4,12(a0)
80007e6c:	00852683          	lw	a3,8(a0)
80007e70:	00452603          	lw	a2,4(a0)
80007e74:	00052583          	lw	a1,0(a0)
80007e78:	34051573          	csrrw	a0,mscratch,a0
80007e7c:	30200073          	mret

80007e80 <plicinit>:
// the riscv Platform Level Interrupt Controller (PLIC).
//

void
plicinit(void)
{
80007e80:	ff010113          	addi	sp,sp,-16
80007e84:	00112623          	sw	ra,12(sp)
80007e88:	00812423          	sw	s0,8(sp)
80007e8c:	01010413          	addi	s0,sp,16
  // set desired IRQ priorities non-zero (otherwise disabled).
  *(uint32*)(PLIC + UART0_IRQ*4) = 1;
80007e90:	0c000737          	lui	a4,0xc000
80007e94:	00100793          	li	a5,1
80007e98:	02f72423          	sw	a5,40(a4) # c000028 <_entry-0x73ffffd8>
  *(uint32*)(PLIC + VIRTIO0_IRQ*4) = 1;
80007e9c:	00f72223          	sw	a5,4(a4)
}
80007ea0:	00c12083          	lw	ra,12(sp)
80007ea4:	00812403          	lw	s0,8(sp)
80007ea8:	01010113          	addi	sp,sp,16
80007eac:	00008067          	ret

80007eb0 <plicinithart>:

void
plicinithart(void)
{
80007eb0:	ff010113          	addi	sp,sp,-16
80007eb4:	00112623          	sw	ra,12(sp)
80007eb8:	00812423          	sw	s0,8(sp)
80007ebc:	01010413          	addi	s0,sp,16
  int hart = cpuid();
80007ec0:	ffffa097          	auipc	ra,0xffffa
80007ec4:	3bc080e7          	jalr	956(ra) # 8000227c <cpuid>
  
  // set uart's enable bit for this hart's S-mode. 
  *(uint32*)PLIC_SENABLE(hart)= (1 << UART0_IRQ) | (1 << VIRTIO0_IRQ);
80007ec8:	00851713          	slli	a4,a0,0x8
80007ecc:	0c0027b7          	lui	a5,0xc002
80007ed0:	00e787b3          	add	a5,a5,a4
80007ed4:	40200713          	li	a4,1026
80007ed8:	08e7a023          	sw	a4,128(a5) # c002080 <_entry-0x73ffdf80>

  // set this hart's S-mode priority threshold to 0.
  *(uint32*)PLIC_SPRIORITY(hart) = 0;
80007edc:	00d51513          	slli	a0,a0,0xd
80007ee0:	0c2017b7          	lui	a5,0xc201
80007ee4:	00a787b3          	add	a5,a5,a0
80007ee8:	0007a023          	sw	zero,0(a5) # c201000 <_entry-0x73dff000>
}
80007eec:	00c12083          	lw	ra,12(sp)
80007ef0:	00812403          	lw	s0,8(sp)
80007ef4:	01010113          	addi	sp,sp,16
80007ef8:	00008067          	ret

80007efc <plic_pending>:

// return a bitmap of which IRQs are waiting
// to be served.
uint32
plic_pending(void)
{
80007efc:	ff010113          	addi	sp,sp,-16
80007f00:	00112623          	sw	ra,12(sp)
80007f04:	00812423          	sw	s0,8(sp)
80007f08:	01010413          	addi	s0,sp,16
  //mask = *(uint32*)(PLIC + 0x1000);
  //mask |= (uint64)*(uint32*)(PLIC + 0x1004) << 32;
  mask = *(uint32*)PLIC_PENDING;

  return mask;
}
80007f0c:	0c0017b7          	lui	a5,0xc001
80007f10:	0007a503          	lw	a0,0(a5) # c001000 <_entry-0x73fff000>
80007f14:	00c12083          	lw	ra,12(sp)
80007f18:	00812403          	lw	s0,8(sp)
80007f1c:	01010113          	addi	sp,sp,16
80007f20:	00008067          	ret

80007f24 <plic_claim>:

// ask the PLIC what interrupt we should serve.
int
plic_claim(void)
{
80007f24:	ff010113          	addi	sp,sp,-16
80007f28:	00112623          	sw	ra,12(sp)
80007f2c:	00812423          	sw	s0,8(sp)
80007f30:	01010413          	addi	s0,sp,16
  int hart = cpuid();
80007f34:	ffffa097          	auipc	ra,0xffffa
80007f38:	348080e7          	jalr	840(ra) # 8000227c <cpuid>
  // int irq = *(uint32*)(PLIC + 0x201004);
  int irq = *(uint32*)PLIC_SCLAIM(hart);
80007f3c:	00d51513          	slli	a0,a0,0xd
80007f40:	0c2017b7          	lui	a5,0xc201
80007f44:	00a787b3          	add	a5,a5,a0
  return irq;
}
80007f48:	0047a503          	lw	a0,4(a5) # c201004 <_entry-0x73dfeffc>
80007f4c:	00c12083          	lw	ra,12(sp)
80007f50:	00812403          	lw	s0,8(sp)
80007f54:	01010113          	addi	sp,sp,16
80007f58:	00008067          	ret

80007f5c <plic_complete>:

// tell the PLIC we've served this IRQ.
void
plic_complete(int irq)
{
80007f5c:	ff010113          	addi	sp,sp,-16
80007f60:	00112623          	sw	ra,12(sp)
80007f64:	00812423          	sw	s0,8(sp)
80007f68:	00912223          	sw	s1,4(sp)
80007f6c:	01010413          	addi	s0,sp,16
80007f70:	00050493          	mv	s1,a0
  int hart = cpuid();
80007f74:	ffffa097          	auipc	ra,0xffffa
80007f78:	308080e7          	jalr	776(ra) # 8000227c <cpuid>
  //*(uint32*)(PLIC + 0x201004) = irq;
  *(uint32*)PLIC_SCLAIM(hart) = irq;
80007f7c:	00d51513          	slli	a0,a0,0xd
80007f80:	0c2017b7          	lui	a5,0xc201
80007f84:	00a787b3          	add	a5,a5,a0
80007f88:	0097a223          	sw	s1,4(a5) # c201004 <_entry-0x73dfeffc>
}
80007f8c:	00c12083          	lw	ra,12(sp)
80007f90:	00812403          	lw	s0,8(sp)
80007f94:	00412483          	lw	s1,4(sp)
80007f98:	01010113          	addi	sp,sp,16
80007f9c:	00008067          	ret

80007fa0 <free_desc>:
}

// mark a descriptor as free.
static void
free_desc(int i)
{
80007fa0:	ff010113          	addi	sp,sp,-16
80007fa4:	00112623          	sw	ra,12(sp)
80007fa8:	00812423          	sw	s0,8(sp)
80007fac:	01010413          	addi	s0,sp,16
  if(i >= NUM)
80007fb0:	00700793          	li	a5,7
80007fb4:	06a7ce63          	blt	a5,a0,80008030 <free_desc+0x90>
    panic("virtio_disk_intr 1");
  if(disk.free[i])
80007fb8:	00019717          	auipc	a4,0x19
80007fbc:	04870713          	addi	a4,a4,72 # 80021000 <disk>
80007fc0:	00a70733          	add	a4,a4,a0
80007fc4:	000027b7          	lui	a5,0x2
80007fc8:	00e787b3          	add	a5,a5,a4
80007fcc:	00c7c783          	lbu	a5,12(a5) # 200c <_entry-0x7fffdff4>
80007fd0:	06079863          	bnez	a5,80008040 <free_desc+0xa0>
    panic("virtio_disk_intr 2");
  disk.desc[i].addr = 0;
80007fd4:	00451713          	slli	a4,a0,0x4
80007fd8:	0001b797          	auipc	a5,0x1b
80007fdc:	0287a783          	lw	a5,40(a5) # 80023000 <disk+0x2000>
80007fe0:	00e787b3          	add	a5,a5,a4
80007fe4:	00000693          	li	a3,0
80007fe8:	00000713          	li	a4,0
80007fec:	00d7a023          	sw	a3,0(a5)
80007ff0:	00e7a223          	sw	a4,4(a5)
  disk.free[i] = 1;
80007ff4:	00019717          	auipc	a4,0x19
80007ff8:	00c70713          	addi	a4,a4,12 # 80021000 <disk>
80007ffc:	00a70733          	add	a4,a4,a0
80008000:	000027b7          	lui	a5,0x2
80008004:	00e787b3          	add	a5,a5,a4
80008008:	00100713          	li	a4,1
8000800c:	00e78623          	sb	a4,12(a5) # 200c <_entry-0x7fffdff4>
  wakeup(&disk.free[0]);
80008010:	0001b517          	auipc	a0,0x1b
80008014:	ffc50513          	addi	a0,a0,-4 # 8002300c <disk+0x200c>
80008018:	ffffb097          	auipc	ra,0xffffb
8000801c:	f14080e7          	jalr	-236(ra) # 80002f2c <wakeup>
}
80008020:	00c12083          	lw	ra,12(sp)
80008024:	00812403          	lw	s0,8(sp)
80008028:	01010113          	addi	sp,sp,16
8000802c:	00008067          	ret
    panic("virtio_disk_intr 1");
80008030:	00001517          	auipc	a0,0x1
80008034:	71850513          	addi	a0,a0,1816 # 80009748 <userret+0x6a8>
80008038:	ffff8097          	auipc	ra,0xffff8
8000803c:	6c4080e7          	jalr	1732(ra) # 800006fc <panic>
    panic("virtio_disk_intr 2");
80008040:	00001517          	auipc	a0,0x1
80008044:	71c50513          	addi	a0,a0,1820 # 8000975c <userret+0x6bc>
80008048:	ffff8097          	auipc	ra,0xffff8
8000804c:	6b4080e7          	jalr	1716(ra) # 800006fc <panic>

80008050 <virtio_disk_init>:
{
80008050:	ff010113          	addi	sp,sp,-16
80008054:	00112623          	sw	ra,12(sp)
80008058:	00812423          	sw	s0,8(sp)
8000805c:	01010413          	addi	s0,sp,16
  initlock(&disk.vdisk_lock, "virtio_disk");
80008060:	00001597          	auipc	a1,0x1
80008064:	71058593          	addi	a1,a1,1808 # 80009770 <userret+0x6d0>
80008068:	0001b517          	auipc	a0,0x1b
8000806c:	ff050513          	addi	a0,a0,-16 # 80023058 <disk+0x2058>
80008070:	ffff9097          	auipc	ra,0xffff9
80008074:	cfc080e7          	jalr	-772(ra) # 80000d6c <initlock>
  if(*R(VIRTIO_MMIO_MAGIC_VALUE) != 0x74726976 ||
80008078:	100017b7          	lui	a5,0x10001
8000807c:	0007a703          	lw	a4,0(a5) # 10001000 <_entry-0x6ffff000>
80008080:	747277b7          	lui	a5,0x74727
80008084:	97678793          	addi	a5,a5,-1674 # 74726976 <_entry-0xb8d968a>
80008088:	12f71263          	bne	a4,a5,800081ac <virtio_disk_init+0x15c>
     *R(VIRTIO_MMIO_VERSION) != 1 ||
8000808c:	100017b7          	lui	a5,0x10001
80008090:	0047a703          	lw	a4,4(a5) # 10001004 <_entry-0x6fffeffc>
  if(*R(VIRTIO_MMIO_MAGIC_VALUE) != 0x74726976 ||
80008094:	00100793          	li	a5,1
80008098:	10f71a63          	bne	a4,a5,800081ac <virtio_disk_init+0x15c>
     *R(VIRTIO_MMIO_DEVICE_ID) != 2 ||
8000809c:	100017b7          	lui	a5,0x10001
800080a0:	0087a703          	lw	a4,8(a5) # 10001008 <_entry-0x6fffeff8>
     *R(VIRTIO_MMIO_VERSION) != 1 ||
800080a4:	00200793          	li	a5,2
800080a8:	10f71263          	bne	a4,a5,800081ac <virtio_disk_init+0x15c>
     *R(VIRTIO_MMIO_VENDOR_ID) != 0x554d4551){
800080ac:	100017b7          	lui	a5,0x10001
800080b0:	00c7a703          	lw	a4,12(a5) # 1000100c <_entry-0x6fffeff4>
     *R(VIRTIO_MMIO_DEVICE_ID) != 2 ||
800080b4:	554d47b7          	lui	a5,0x554d4
800080b8:	55178793          	addi	a5,a5,1361 # 554d4551 <_entry-0x2ab2baaf>
800080bc:	0ef71863          	bne	a4,a5,800081ac <virtio_disk_init+0x15c>
  *R(VIRTIO_MMIO_STATUS) = status;
800080c0:	100017b7          	lui	a5,0x10001
800080c4:	00100713          	li	a4,1
800080c8:	06e7a823          	sw	a4,112(a5) # 10001070 <_entry-0x6fffef90>
  *R(VIRTIO_MMIO_STATUS) = status;
800080cc:	00300713          	li	a4,3
800080d0:	06e7a823          	sw	a4,112(a5)
  uint32 features = *R(VIRTIO_MMIO_DEVICE_FEATURES);
800080d4:	10001737          	lui	a4,0x10001
800080d8:	01072703          	lw	a4,16(a4) # 10001010 <_entry-0x6fffeff0>
  features &= ~(1 << VIRTIO_RING_F_INDIRECT_DESC);
800080dc:	c7ffe6b7          	lui	a3,0xc7ffe
800080e0:	75f68693          	addi	a3,a3,1887 # c7ffe75f <end+0x47fda74b>
800080e4:	00d77733          	and	a4,a4,a3
  *R(VIRTIO_MMIO_DRIVER_FEATURES) = features;
800080e8:	100016b7          	lui	a3,0x10001
800080ec:	02e6a023          	sw	a4,32(a3) # 10001020 <_entry-0x6fffefe0>
  *R(VIRTIO_MMIO_STATUS) = status;
800080f0:	00b00713          	li	a4,11
800080f4:	06e7a823          	sw	a4,112(a5)
  *R(VIRTIO_MMIO_STATUS) = status;
800080f8:	00f00713          	li	a4,15
800080fc:	06e7a823          	sw	a4,112(a5)
  *R(VIRTIO_MMIO_GUEST_PAGE_SIZE) = PGSIZE;
80008100:	00001737          	lui	a4,0x1
80008104:	02e6a423          	sw	a4,40(a3)
  *R(VIRTIO_MMIO_QUEUE_SEL) = 0;
80008108:	0206a823          	sw	zero,48(a3)
  uint32 max = *R(VIRTIO_MMIO_QUEUE_NUM_MAX);
8000810c:	0346a783          	lw	a5,52(a3)
  if(max == 0)
80008110:	0a078663          	beqz	a5,800081bc <virtio_disk_init+0x16c>
  if(max < NUM)
80008114:	00700713          	li	a4,7
80008118:	0af77a63          	bgeu	a4,a5,800081cc <virtio_disk_init+0x17c>
  *R(VIRTIO_MMIO_QUEUE_NUM) = NUM;
8000811c:	100017b7          	lui	a5,0x10001
80008120:	00800713          	li	a4,8
80008124:	02e7ac23          	sw	a4,56(a5) # 10001038 <_entry-0x6fffefc8>
  memset(disk.pages, 0, sizeof(disk.pages));
80008128:	00002637          	lui	a2,0x2
8000812c:	00000593          	li	a1,0
80008130:	00019517          	auipc	a0,0x19
80008134:	ed050513          	addi	a0,a0,-304 # 80021000 <disk>
80008138:	ffff9097          	auipc	ra,0xffff9
8000813c:	e98080e7          	jalr	-360(ra) # 80000fd0 <memset>
  *R(VIRTIO_MMIO_QUEUE_PFN) = ((uint32)disk.pages) >> PGSHIFT;
80008140:	00019717          	auipc	a4,0x19
80008144:	ec070713          	addi	a4,a4,-320 # 80021000 <disk>
80008148:	00c75693          	srli	a3,a4,0xc
8000814c:	100017b7          	lui	a5,0x10001
80008150:	04d7a023          	sw	a3,64(a5) # 10001040 <_entry-0x6fffefc0>
  disk.desc = (struct VRingDesc *) disk.pages;
80008154:	0001b797          	auipc	a5,0x1b
80008158:	eac78793          	addi	a5,a5,-340 # 80023000 <disk+0x2000>
8000815c:	00e7a023          	sw	a4,0(a5)
  disk.avail = (uint16*)(((char*)disk.desc) + NUM*sizeof(struct VRingDesc));
80008160:	00019717          	auipc	a4,0x19
80008164:	f2070713          	addi	a4,a4,-224 # 80021080 <disk+0x80>
80008168:	00e7a223          	sw	a4,4(a5)
  disk.used = (struct UsedArea *) (disk.pages + PGSIZE);
8000816c:	0001a717          	auipc	a4,0x1a
80008170:	e9470713          	addi	a4,a4,-364 # 80022000 <disk+0x1000>
80008174:	00e7a423          	sw	a4,8(a5)
    disk.free[i] = 1;
80008178:	00100713          	li	a4,1
8000817c:	00e78623          	sb	a4,12(a5)
80008180:	00e786a3          	sb	a4,13(a5)
80008184:	00e78723          	sb	a4,14(a5)
80008188:	00e787a3          	sb	a4,15(a5)
8000818c:	00e78823          	sb	a4,16(a5)
80008190:	00e788a3          	sb	a4,17(a5)
80008194:	00e78923          	sb	a4,18(a5)
80008198:	00e789a3          	sb	a4,19(a5)
}
8000819c:	00c12083          	lw	ra,12(sp)
800081a0:	00812403          	lw	s0,8(sp)
800081a4:	01010113          	addi	sp,sp,16
800081a8:	00008067          	ret
    panic("could not find virtio disk");
800081ac:	00001517          	auipc	a0,0x1
800081b0:	5d050513          	addi	a0,a0,1488 # 8000977c <userret+0x6dc>
800081b4:	ffff8097          	auipc	ra,0xffff8
800081b8:	548080e7          	jalr	1352(ra) # 800006fc <panic>
    panic("virtio disk has no queue 0");
800081bc:	00001517          	auipc	a0,0x1
800081c0:	5dc50513          	addi	a0,a0,1500 # 80009798 <userret+0x6f8>
800081c4:	ffff8097          	auipc	ra,0xffff8
800081c8:	538080e7          	jalr	1336(ra) # 800006fc <panic>
    panic("virtio disk max queue too short");
800081cc:	00001517          	auipc	a0,0x1
800081d0:	5e850513          	addi	a0,a0,1512 # 800097b4 <userret+0x714>
800081d4:	ffff8097          	auipc	ra,0xffff8
800081d8:	528080e7          	jalr	1320(ra) # 800006fc <panic>

800081dc <virtio_disk_rw>:
  return 0;
}

void
virtio_disk_rw(struct buf *b, int write)
{
800081dc:	fb010113          	addi	sp,sp,-80
800081e0:	04112623          	sw	ra,76(sp)
800081e4:	04812423          	sw	s0,72(sp)
800081e8:	04912223          	sw	s1,68(sp)
800081ec:	05212023          	sw	s2,64(sp)
800081f0:	03312e23          	sw	s3,60(sp)
800081f4:	03412c23          	sw	s4,56(sp)
800081f8:	03512a23          	sw	s5,52(sp)
800081fc:	03612823          	sw	s6,48(sp)
80008200:	03712623          	sw	s7,44(sp)
80008204:	03812423          	sw	s8,40(sp)
80008208:	05010413          	addi	s0,sp,80
8000820c:	00050a93          	mv	s5,a0
80008210:	00058b93          	mv	s7,a1
  uint64 sector = b->blockno * (BSIZE / 512);
80008214:	00c52c03          	lw	s8,12(a0)
80008218:	001c1c13          	slli	s8,s8,0x1

  acquire(&disk.vdisk_lock);
8000821c:	0001b517          	auipc	a0,0x1b
80008220:	e3c50513          	addi	a0,a0,-452 # 80023058 <disk+0x2058>
80008224:	ffff9097          	auipc	ra,0xffff9
80008228:	cd8080e7          	jalr	-808(ra) # 80000efc <acquire>
    if(disk.free[i]){
8000822c:	00002937          	lui	s2,0x2
80008230:	00c90913          	addi	s2,s2,12 # 200c <_entry-0x7fffdff4>
80008234:	00019497          	auipc	s1,0x19
80008238:	dcc48493          	addi	s1,s1,-564 # 80021000 <disk>
  for(int i = 0; i < NUM; i++){
8000823c:	00800993          	li	s3,8
      disk.free[i] = 0;
80008240:	00002b37          	lui	s6,0x2
80008244:	0880006f          	j	800082cc <virtio_disk_rw+0xf0>
80008248:	00f48733          	add	a4,s1,a5
8000824c:	00eb0733          	add	a4,s6,a4
80008250:	00070623          	sb	zero,12(a4)
    idx[i] = alloc_desc();
80008254:	00f62023          	sw	a5,0(a2) # 2000 <_entry-0x7fffe000>
    if(idx[i] < 0){
80008258:	0207cc63          	bltz	a5,80008290 <virtio_disk_rw+0xb4>
  for(int i = 0; i < 3; i++){
8000825c:	001a0a13          	addi	s4,s4,1
80008260:	00468693          	addi	a3,a3,4
80008264:	20ba0e63          	beq	s4,a1,80008480 <virtio_disk_rw+0x2a4>
    idx[i] = alloc_desc();
80008268:	00068613          	mv	a2,a3
  for(int i = 0; i < NUM; i++){
8000826c:	00000793          	li	a5,0
    if(disk.free[i]){
80008270:	01278733          	add	a4,a5,s2
80008274:	00970733          	add	a4,a4,s1
80008278:	00074703          	lbu	a4,0(a4)
8000827c:	fc0716e3          	bnez	a4,80008248 <virtio_disk_rw+0x6c>
  for(int i = 0; i < NUM; i++){
80008280:	00178793          	addi	a5,a5,1
80008284:	ff3796e3          	bne	a5,s3,80008270 <virtio_disk_rw+0x94>
    idx[i] = alloc_desc();
80008288:	fff00793          	li	a5,-1
8000828c:	00f62023          	sw	a5,0(a2)
      for(int j = 0; j < i; j++)
80008290:	03405263          	blez	s4,800082b4 <virtio_disk_rw+0xd8>
        free_desc(idx[j]);
80008294:	fc442503          	lw	a0,-60(s0)
80008298:	00000097          	auipc	ra,0x0
8000829c:	d08080e7          	jalr	-760(ra) # 80007fa0 <free_desc>
      for(int j = 0; j < i; j++)
800082a0:	00100793          	li	a5,1
800082a4:	0147d863          	bge	a5,s4,800082b4 <virtio_disk_rw+0xd8>
        free_desc(idx[j]);
800082a8:	fc842503          	lw	a0,-56(s0)
800082ac:	00000097          	auipc	ra,0x0
800082b0:	cf4080e7          	jalr	-780(ra) # 80007fa0 <free_desc>
  int idx[3];
  while(1){
    if(alloc3_desc(idx) == 0) {
      break;
    }
    sleep(&disk.free[0], &disk.vdisk_lock);
800082b4:	0001b597          	auipc	a1,0x1b
800082b8:	da458593          	addi	a1,a1,-604 # 80023058 <disk+0x2058>
800082bc:	0001b517          	auipc	a0,0x1b
800082c0:	d5050513          	addi	a0,a0,-688 # 8002300c <disk+0x200c>
800082c4:	ffffb097          	auipc	ra,0xffffb
800082c8:	a58080e7          	jalr	-1448(ra) # 80002d1c <sleep>
  for(int i = 0; i < 3; i++){
800082cc:	fc440693          	addi	a3,s0,-60
800082d0:	00000a13          	li	s4,0
800082d4:	00300593          	li	a1,3
800082d8:	f91ff06f          	j	80008268 <virtio_disk_rw+0x8c>
  disk.desc[idx[0]].next = idx[1];

  disk.desc[idx[1]].addr = ((uint32) b->data) & 0xffffffff; // XXX
  disk.desc[idx[1]].len = BSIZE;
  if(write)
    disk.desc[idx[1]].flags = 0; // device reads b->data
800082dc:	0001b717          	auipc	a4,0x1b
800082e0:	d2472703          	lw	a4,-732(a4) # 80023000 <disk+0x2000>
800082e4:	00f70733          	add	a4,a4,a5
800082e8:	00071623          	sh	zero,12(a4)
  else
    disk.desc[idx[1]].flags = VRING_DESC_F_WRITE; // device writes b->data
  disk.desc[idx[1]].flags |= VRING_DESC_F_NEXT;
800082ec:	00019897          	auipc	a7,0x19
800082f0:	d1488893          	addi	a7,a7,-748 # 80021000 <disk>
800082f4:	0001b717          	auipc	a4,0x1b
800082f8:	d0c70713          	addi	a4,a4,-756 # 80023000 <disk+0x2000>
800082fc:	00072683          	lw	a3,0(a4)
80008300:	00f686b3          	add	a3,a3,a5
80008304:	00c6d603          	lhu	a2,12(a3)
80008308:	00166613          	ori	a2,a2,1
8000830c:	00c69623          	sh	a2,12(a3)
  disk.desc[idx[1]].next = idx[2];
80008310:	fcc42683          	lw	a3,-52(s0)
80008314:	00072603          	lw	a2,0(a4)
80008318:	00f607b3          	add	a5,a2,a5
8000831c:	00d79723          	sh	a3,14(a5)

  disk.info[idx[0]].status = 0;
80008320:	40058613          	addi	a2,a1,1024
80008324:	00361613          	slli	a2,a2,0x3
80008328:	00c88633          	add	a2,a7,a2
8000832c:	00060e23          	sb	zero,28(a2)
  disk.desc[idx[2]].addr = ((uint32) &disk.info[idx[0]].status) & 0xffffffff; // XXX
80008330:	00469793          	slli	a5,a3,0x4
80008334:	00072503          	lw	a0,0(a4)
80008338:	00f50533          	add	a0,a0,a5
8000833c:	00359693          	slli	a3,a1,0x3
80008340:	00002837          	lui	a6,0x2
80008344:	01c80813          	addi	a6,a6,28 # 201c <_entry-0x7fffdfe4>
80008348:	010686b3          	add	a3,a3,a6
8000834c:	011686b3          	add	a3,a3,a7
80008350:	00d52023          	sw	a3,0(a0)
80008354:	00052223          	sw	zero,4(a0)
  disk.desc[idx[2]].len = 1;
80008358:	00072683          	lw	a3,0(a4)
8000835c:	00f686b3          	add	a3,a3,a5
80008360:	00100513          	li	a0,1
80008364:	00a6a423          	sw	a0,8(a3)
  disk.desc[idx[2]].flags = VRING_DESC_F_WRITE; // device writes the status
80008368:	00072683          	lw	a3,0(a4)
8000836c:	00f686b3          	add	a3,a3,a5
80008370:	00200813          	li	a6,2
80008374:	01069623          	sh	a6,12(a3)
  disk.desc[idx[2]].next = 0;
80008378:	00072683          	lw	a3,0(a4)
8000837c:	00f687b3          	add	a5,a3,a5
80008380:	00079723          	sh	zero,14(a5)

  // record struct buf for virtio_disk_intr().
  b->disk = 1;
80008384:	00aaa223          	sw	a0,4(s5) # 1004 <_entry-0x7fffeffc>
  disk.info[idx[0]].b = b;
80008388:	01562c23          	sw	s5,24(a2)

  // avail[0] is flags
  // avail[1] tells the device how far to look in avail[2...].
  // avail[2...] are desc[] indices the device should process.
  // we only tell device the first index in our chain of descriptors.
  disk.avail[2 + (disk.avail[1] % NUM)] = idx[0];
8000838c:	00472683          	lw	a3,4(a4)
80008390:	0026d783          	lhu	a5,2(a3)
80008394:	0077f793          	andi	a5,a5,7
80008398:	010787b3          	add	a5,a5,a6
8000839c:	00179793          	slli	a5,a5,0x1
800083a0:	00f686b3          	add	a3,a3,a5
800083a4:	00b69023          	sh	a1,0(a3)
  __sync_synchronize();
800083a8:	0330000f          	fence	rw,rw
  disk.avail[1] = disk.avail[1] + 1;
800083ac:	00472703          	lw	a4,4(a4)
800083b0:	00275783          	lhu	a5,2(a4)
800083b4:	00a787b3          	add	a5,a5,a0
800083b8:	00f71123          	sh	a5,2(a4)

  *R(VIRTIO_MMIO_QUEUE_NOTIFY) = 0; // value is queue number
800083bc:	100017b7          	lui	a5,0x10001
800083c0:	0407a823          	sw	zero,80(a5) # 10001050 <_entry-0x6fffefb0>

  // Wait for virtio_disk_intr() to say request has finished.
  while(b->disk == 1) {
800083c4:	004aa783          	lw	a5,4(s5)
800083c8:	02a79463          	bne	a5,a0,800083f0 <virtio_disk_rw+0x214>
    sleep(b, &disk.vdisk_lock);
800083cc:	0001b917          	auipc	s2,0x1b
800083d0:	c8c90913          	addi	s2,s2,-884 # 80023058 <disk+0x2058>
  while(b->disk == 1) {
800083d4:	00078493          	mv	s1,a5
    sleep(b, &disk.vdisk_lock);
800083d8:	00090593          	mv	a1,s2
800083dc:	000a8513          	mv	a0,s5
800083e0:	ffffb097          	auipc	ra,0xffffb
800083e4:	93c080e7          	jalr	-1732(ra) # 80002d1c <sleep>
  while(b->disk == 1) {
800083e8:	004aa783          	lw	a5,4(s5)
800083ec:	fe9786e3          	beq	a5,s1,800083d8 <virtio_disk_rw+0x1fc>
  }

  disk.info[idx[0]].b = 0;
800083f0:	fc442483          	lw	s1,-60(s0)
800083f4:	40048713          	addi	a4,s1,1024
800083f8:	00371713          	slli	a4,a4,0x3
800083fc:	00019797          	auipc	a5,0x19
80008400:	c0478793          	addi	a5,a5,-1020 # 80021000 <disk>
80008404:	00e787b3          	add	a5,a5,a4
80008408:	0007ac23          	sw	zero,24(a5)
    if(disk.desc[i].flags & VRING_DESC_F_NEXT)
8000840c:	0001b917          	auipc	s2,0x1b
80008410:	bf490913          	addi	s2,s2,-1036 # 80023000 <disk+0x2000>
    free_desc(i);
80008414:	00048513          	mv	a0,s1
80008418:	00000097          	auipc	ra,0x0
8000841c:	b88080e7          	jalr	-1144(ra) # 80007fa0 <free_desc>
    if(disk.desc[i].flags & VRING_DESC_F_NEXT)
80008420:	00449493          	slli	s1,s1,0x4
80008424:	00092783          	lw	a5,0(s2)
80008428:	009787b3          	add	a5,a5,s1
8000842c:	00c7d703          	lhu	a4,12(a5)
80008430:	00177713          	andi	a4,a4,1
80008434:	00070663          	beqz	a4,80008440 <virtio_disk_rw+0x264>
      i = disk.desc[i].next;
80008438:	00e7d483          	lhu	s1,14(a5)
    free_desc(i);
8000843c:	fd9ff06f          	j	80008414 <virtio_disk_rw+0x238>
  free_chain(idx[0]);

  release(&disk.vdisk_lock);
80008440:	0001b517          	auipc	a0,0x1b
80008444:	c1850513          	addi	a0,a0,-1000 # 80023058 <disk+0x2058>
80008448:	ffff9097          	auipc	ra,0xffff9
8000844c:	b28080e7          	jalr	-1240(ra) # 80000f70 <release>
}
80008450:	04c12083          	lw	ra,76(sp)
80008454:	04812403          	lw	s0,72(sp)
80008458:	04412483          	lw	s1,68(sp)
8000845c:	04012903          	lw	s2,64(sp)
80008460:	03c12983          	lw	s3,60(sp)
80008464:	03812a03          	lw	s4,56(sp)
80008468:	03412a83          	lw	s5,52(sp)
8000846c:	03012b03          	lw	s6,48(sp)
80008470:	02c12b83          	lw	s7,44(sp)
80008474:	02812c03          	lw	s8,40(sp)
80008478:	05010113          	addi	sp,sp,80
8000847c:	00008067          	ret
  if(write)
80008480:	017037b3          	snez	a5,s7
80008484:	faf42823          	sw	a5,-80(s0)
  buf0.reserved = 0;
80008488:	fa042a23          	sw	zero,-76(s0)
  buf0.sector = sector;
8000848c:	fb842c23          	sw	s8,-72(s0)
80008490:	fa042e23          	sw	zero,-68(s0)
  disk.desc[idx[0]].addr = kvmpa((uint32) &buf0);
80008494:	fb040513          	addi	a0,s0,-80
80008498:	ffff9097          	auipc	ra,0xffff9
8000849c:	0dc080e7          	jalr	220(ra) # 80001574 <kvmpa>
800084a0:	fc442583          	lw	a1,-60(s0)
800084a4:	00459693          	slli	a3,a1,0x4
800084a8:	0001b717          	auipc	a4,0x1b
800084ac:	b5870713          	addi	a4,a4,-1192 # 80023000 <disk+0x2000>
800084b0:	00072783          	lw	a5,0(a4)
800084b4:	00d787b3          	add	a5,a5,a3
800084b8:	00a7a023          	sw	a0,0(a5)
800084bc:	0007a223          	sw	zero,4(a5)
  disk.desc[idx[0]].len = sizeof(buf0);
800084c0:	00072783          	lw	a5,0(a4)
800084c4:	00d787b3          	add	a5,a5,a3
800084c8:	01000613          	li	a2,16
800084cc:	00c7a423          	sw	a2,8(a5)
  disk.desc[idx[0]].flags = VRING_DESC_F_NEXT;
800084d0:	00072783          	lw	a5,0(a4)
800084d4:	00d787b3          	add	a5,a5,a3
800084d8:	00100613          	li	a2,1
800084dc:	00c79623          	sh	a2,12(a5)
  disk.desc[idx[0]].next = idx[1];
800084e0:	fc842783          	lw	a5,-56(s0)
800084e4:	00072603          	lw	a2,0(a4)
800084e8:	00d606b3          	add	a3,a2,a3
800084ec:	00f69723          	sh	a5,14(a3)
  disk.desc[idx[1]].addr = ((uint32) b->data) & 0xffffffff; // XXX
800084f0:	00479793          	slli	a5,a5,0x4
800084f4:	00072683          	lw	a3,0(a4)
800084f8:	00f686b3          	add	a3,a3,a5
800084fc:	038a8613          	addi	a2,s5,56
80008500:	00c6a023          	sw	a2,0(a3)
80008504:	0006a223          	sw	zero,4(a3)
  disk.desc[idx[1]].len = BSIZE;
80008508:	00072703          	lw	a4,0(a4)
8000850c:	00f70733          	add	a4,a4,a5
80008510:	40000693          	li	a3,1024
80008514:	00d72423          	sw	a3,8(a4)
  if(write)
80008518:	dc0b92e3          	bnez	s7,800082dc <virtio_disk_rw+0x100>
    disk.desc[idx[1]].flags = VRING_DESC_F_WRITE; // device writes b->data
8000851c:	0001b717          	auipc	a4,0x1b
80008520:	ae472703          	lw	a4,-1308(a4) # 80023000 <disk+0x2000>
80008524:	00f70733          	add	a4,a4,a5
80008528:	00200693          	li	a3,2
8000852c:	00d71623          	sh	a3,12(a4)
80008530:	dbdff06f          	j	800082ec <virtio_disk_rw+0x110>

80008534 <virtio_disk_intr>:

void
virtio_disk_intr()
{
80008534:	ff010113          	addi	sp,sp,-16
80008538:	00112623          	sw	ra,12(sp)
8000853c:	00812423          	sw	s0,8(sp)
80008540:	01010413          	addi	s0,sp,16
  acquire(&disk.vdisk_lock);
80008544:	0001b517          	auipc	a0,0x1b
80008548:	b1450513          	addi	a0,a0,-1260 # 80023058 <disk+0x2058>
8000854c:	ffff9097          	auipc	ra,0xffff9
80008550:	9b0080e7          	jalr	-1616(ra) # 80000efc <acquire>

  while((disk.used_idx % NUM) != (disk.used->id % NUM)){
80008554:	0001b717          	auipc	a4,0x1b
80008558:	aac70713          	addi	a4,a4,-1364 # 80023000 <disk+0x2000>
8000855c:	01475783          	lhu	a5,20(a4)
80008560:	00872703          	lw	a4,8(a4)
80008564:	00275683          	lhu	a3,2(a4)
80008568:	00d7c6b3          	xor	a3,a5,a3
8000856c:	0076f693          	andi	a3,a3,7
80008570:	08068263          	beqz	a3,800085f4 <virtio_disk_intr+0xc0>
80008574:	00912223          	sw	s1,4(sp)
80008578:	01212023          	sw	s2,0(sp)
    int id = disk.used->elems[disk.used_idx].id;

    if(disk.info[id].status != 0)
8000857c:	00019917          	auipc	s2,0x19
80008580:	a8490913          	addi	s2,s2,-1404 # 80021000 <disk>
      panic("virtio_disk_intr status");
    
    disk.info[id].b->disk = 0;   // disk is done with buf
    wakeup(disk.info[id].b);

    disk.used_idx = (disk.used_idx + 1) % NUM;
80008584:	0001b497          	auipc	s1,0x1b
80008588:	a7c48493          	addi	s1,s1,-1412 # 80023000 <disk+0x2000>
    int id = disk.used->elems[disk.used_idx].id;
8000858c:	00379793          	slli	a5,a5,0x3
80008590:	00f70733          	add	a4,a4,a5
80008594:	00472783          	lw	a5,4(a4)
    if(disk.info[id].status != 0)
80008598:	40078713          	addi	a4,a5,1024
8000859c:	00371713          	slli	a4,a4,0x3
800085a0:	00e90733          	add	a4,s2,a4
800085a4:	01c74703          	lbu	a4,28(a4)
800085a8:	06071663          	bnez	a4,80008614 <virtio_disk_intr+0xe0>
    disk.info[id].b->disk = 0;   // disk is done with buf
800085ac:	40078793          	addi	a5,a5,1024
800085b0:	00379793          	slli	a5,a5,0x3
800085b4:	00f907b3          	add	a5,s2,a5
800085b8:	0187a703          	lw	a4,24(a5)
800085bc:	00072223          	sw	zero,4(a4)
    wakeup(disk.info[id].b);
800085c0:	0187a503          	lw	a0,24(a5)
800085c4:	ffffb097          	auipc	ra,0xffffb
800085c8:	968080e7          	jalr	-1688(ra) # 80002f2c <wakeup>
    disk.used_idx = (disk.used_idx + 1) % NUM;
800085cc:	0144d783          	lhu	a5,20(s1)
800085d0:	00178793          	addi	a5,a5,1
800085d4:	0077f793          	andi	a5,a5,7
800085d8:	00f49a23          	sh	a5,20(s1)
  while((disk.used_idx % NUM) != (disk.used->id % NUM)){
800085dc:	0084a703          	lw	a4,8(s1)
800085e0:	00275683          	lhu	a3,2(a4)
800085e4:	0076f693          	andi	a3,a3,7
800085e8:	faf692e3          	bne	a3,a5,8000858c <virtio_disk_intr+0x58>
800085ec:	00412483          	lw	s1,4(sp)
800085f0:	00012903          	lw	s2,0(sp)
  }

  release(&disk.vdisk_lock);
800085f4:	0001b517          	auipc	a0,0x1b
800085f8:	a6450513          	addi	a0,a0,-1436 # 80023058 <disk+0x2058>
800085fc:	ffff9097          	auipc	ra,0xffff9
80008600:	974080e7          	jalr	-1676(ra) # 80000f70 <release>
}
80008604:	00c12083          	lw	ra,12(sp)
80008608:	00812403          	lw	s0,8(sp)
8000860c:	01010113          	addi	sp,sp,16
80008610:	00008067          	ret
      panic("virtio_disk_intr status");
80008614:	00001517          	auipc	a0,0x1
80008618:	1c050513          	addi	a0,a0,448 # 800097d4 <userret+0x734>
8000861c:	ffff8097          	auipc	ra,0xffff8
80008620:	0e0080e7          	jalr	224(ra) # 800006fc <panic>
	...

80009000 <trampoline>:
80009000:	14051573          	csrrw	a0,sscratch,a0
80009004:	00152a23          	sw	ra,20(a0)
80009008:	00252c23          	sw	sp,24(a0)
8000900c:	00352e23          	sw	gp,28(a0)
80009010:	02452023          	sw	tp,32(a0)
80009014:	02552223          	sw	t0,36(a0)
80009018:	02652423          	sw	t1,40(a0)
8000901c:	02752623          	sw	t2,44(a0)
80009020:	02852823          	sw	s0,48(a0)
80009024:	02952a23          	sw	s1,52(a0)
80009028:	02b52e23          	sw	a1,60(a0)
8000902c:	04c52023          	sw	a2,64(a0)
80009030:	04d52223          	sw	a3,68(a0)
80009034:	04e52423          	sw	a4,72(a0)
80009038:	04f52623          	sw	a5,76(a0)
8000903c:	05052823          	sw	a6,80(a0)
80009040:	05152a23          	sw	a7,84(a0)
80009044:	05252c23          	sw	s2,88(a0)
80009048:	05352e23          	sw	s3,92(a0)
8000904c:	07452023          	sw	s4,96(a0)
80009050:	07552223          	sw	s5,100(a0)
80009054:	07652423          	sw	s6,104(a0)
80009058:	07752623          	sw	s7,108(a0)
8000905c:	07852823          	sw	s8,112(a0)
80009060:	07952a23          	sw	s9,116(a0)
80009064:	07a52c23          	sw	s10,120(a0)
80009068:	07b52e23          	sw	s11,124(a0)
8000906c:	09c52023          	sw	t3,128(a0)
80009070:	09d52223          	sw	t4,132(a0)
80009074:	09e52423          	sw	t5,136(a0)
80009078:	09f52623          	sw	t6,140(a0)
8000907c:	140022f3          	csrr	t0,sscratch
80009080:	02552c23          	sw	t0,56(a0)
80009084:	00452103          	lw	sp,4(a0)
80009088:	01052203          	lw	tp,16(a0)
8000908c:	00852283          	lw	t0,8(a0)
80009090:	00052303          	lw	t1,0(a0)
80009094:	18031073          	csrw	satp,t1
80009098:	12000073          	sfence.vma
8000909c:	00028067          	jr	t0

800090a0 <userret>:
800090a0:	18059073          	csrw	satp,a1
800090a4:	12000073          	sfence.vma
800090a8:	03852283          	lw	t0,56(a0)
800090ac:	14029073          	csrw	sscratch,t0
800090b0:	01452083          	lw	ra,20(a0)
800090b4:	01852103          	lw	sp,24(a0)
800090b8:	01c52183          	lw	gp,28(a0)
800090bc:	02052203          	lw	tp,32(a0)
800090c0:	02452283          	lw	t0,36(a0)
800090c4:	02852303          	lw	t1,40(a0)
800090c8:	02c52383          	lw	t2,44(a0)
800090cc:	03052403          	lw	s0,48(a0)
800090d0:	03452483          	lw	s1,52(a0)
800090d4:	03c52583          	lw	a1,60(a0)
800090d8:	04052603          	lw	a2,64(a0)
800090dc:	04452683          	lw	a3,68(a0)
800090e0:	04852703          	lw	a4,72(a0)
800090e4:	04c52783          	lw	a5,76(a0)
800090e8:	05052803          	lw	a6,80(a0)
800090ec:	05452883          	lw	a7,84(a0)
800090f0:	05852903          	lw	s2,88(a0)
800090f4:	05c52983          	lw	s3,92(a0)
800090f8:	06052a03          	lw	s4,96(a0)
800090fc:	06452a83          	lw	s5,100(a0)
80009100:	06852b03          	lw	s6,104(a0)
80009104:	06c52b83          	lw	s7,108(a0)
80009108:	07052c03          	lw	s8,112(a0)
8000910c:	07452c83          	lw	s9,116(a0)
80009110:	07852d03          	lw	s10,120(a0)
80009114:	07c52d83          	lw	s11,124(a0)
80009118:	08052e03          	lw	t3,128(a0)
8000911c:	08452e83          	lw	t4,132(a0)
80009120:	08852f03          	lw	t5,136(a0)
80009124:	08c52f83          	lw	t6,140(a0)
80009128:	14051573          	csrrw	a0,sscratch,a0
8000912c:	10200073          	sret
