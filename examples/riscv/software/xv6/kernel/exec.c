#include "types.h"
#include "param.h"
#include "memlayout.h"
#include "riscv.h"
#include "spinlock.h"
#include "proc.h"
#include "defs.h"
#include "elf.h"

static int loadseg(pde_t *pgdir, uint32 addr, struct inode *ip, uint offset, uint sz);

int
exec(char *path, char **argv)
{
  char *s, *last;
  int i, off;
  uint32 argc, sz, sp, ustack[MAXARG+1], stackbase;
  int fail_step = 0;
  struct elfhdr elf;
  struct inode *ip;
  struct proghdr ph;
  pagetable_t pagetable = 0, oldpagetable;
  struct proc *p = myproc();

  begin_op();

  if((ip = namei(path)) == 0){
    fail_step = 1;
    end_op();
    return -1;
  }
  ilock(ip);

  // Check ELF header
  if(readi(ip, 0, (uint32)&elf, 0, sizeof(elf)) != sizeof(elf)) {
    fail_step = 2;
    goto bad;
  }
  if(elf.magic != ELF_MAGIC) {
    fail_step = 3;
    goto bad;
  }

  if((pagetable = proc_pagetable(p)) == 0) {
    fail_step = 4;
    goto bad;
  }

  // Load program into memory.
  sz = 0;
  for(i=0, off=elf.phoff; i<elf.phnum; i++, off+=sizeof(ph)){



    if(readi(ip, 0, (uint32)&ph, off, sizeof(ph)) != sizeof(ph)) {
      fail_step = 5;
      goto bad;
    }

    if(ph.type != ELF_PROG_LOAD)
      continue;
    if(ph.memsz < ph.filesz) {
      fail_step = 6;
      goto bad;
    }
    if(ph.vaddr + ph.memsz < ph.vaddr) {
      fail_step = 7;
      goto bad;
    }
    if((sz = uvmalloc(pagetable, sz, ph.vaddr + ph.memsz)) == 0) {
      fail_step = 8;
      goto bad;
    }
    if(ph.vaddr % PGSIZE != 0) {
      fail_step = 9;
      printf("exec ph misalign path=%s off=%d vaddr=0x%x filesz=0x%x memsz=0x%x type=0x%x\n",
             path, off, ph.vaddr, ph.filesz, ph.memsz, ph.type);
      goto bad;
    }
    if(loadseg(pagetable, ph.vaddr, ip, ph.off, ph.filesz) < 0) {
      fail_step = 10;
      goto bad;
    }
  }
  iunlockput(ip);
  end_op();
  ip = 0;

  p = myproc();
  uint32 oldsz = p->sz;

  // Allocate two pages at the next page boundary.
  // Use the second as the user stack.
  sz = PGROUNDUP(sz);
  if((sz = uvmalloc(pagetable, sz, sz + 2*PGSIZE)) == 0) {
    fail_step = 11;
    goto bad;
  }
  uvmclear(pagetable, sz-2*PGSIZE);
  sp = sz;
  stackbase = sp - PGSIZE;

  // Push argument strings, prepare rest of stack in ustack.
  for(argc = 0; argv[argc]; argc++) {
    if(argc >= MAXARG) {
      fail_step = 12;
      goto bad;
    }
    sp -= strlen(argv[argc]) + 1;
    sp -= sp % 16; // riscv sp must be 16-byte aligned
    if(sp < stackbase) {
      fail_step = 13;
      goto bad;
    }
    if(copyout(pagetable, sp, argv[argc], strlen(argv[argc]) + 1) < 0) {
      fail_step = 14;
      goto bad;
    }
    ustack[argc] = sp;
  }
  ustack[argc] = 0;

  // push the array of argv[] pointers.
  sp -= (argc+1) * sizeof(uint32);
  sp -= sp % 16;
  if(sp < stackbase) {
    fail_step = 15;
    goto bad;
  }
  if(copyout(pagetable, sp, (char *)ustack, (argc+1)*sizeof(uint32)) < 0) {
    fail_step = 16;
    goto bad;
  }

  // arguments to user main(argc, argv)
  // argc is returned via the system call return
  // value, which goes in a0.
  p->tf->a1 = sp;

  // Save program name for debugging.
  for(last=s=path; *s; s++)
    if(*s == '/')
      last = s+1;
  safestrcpy(p->name, last, sizeof(p->name));
    
  // Commit to the user image.
  oldpagetable = p->pagetable;
  p->pagetable = pagetable;
  p->sz = sz;
  p->tf->epc = elf.entry;  // initial program counter = main
  p->tf->sp = sp; // initial stack pointer
  proc_freepagetable(oldpagetable, oldsz);
  return argc; // this ends up in a0, the first argument to main(argc, argv)

 bad:
  printf("exec fail step=%d path=%s\n", fail_step, path);
  if(pagetable)
    proc_freepagetable(pagetable, sz);
  if(ip){
    iunlockput(ip);
    end_op();
  }
  return -1;
}

// Load a program segment into pagetable at virtual address va.
// va must be page-aligned
// and the pages from va to va+sz must already be mapped.
// Returns 0 on success, -1 on failure.
static int
loadseg(pagetable_t pagetable, uint32 va, struct inode *ip, uint offset, uint sz)
{
  uint i, n;
  uint32 pa;

  if((va % PGSIZE) != 0)
    panic("loadseg: va must be page aligned");

  for(i = 0; i < sz; i += PGSIZE){
    pa = walkaddr(pagetable, va + i);
    if(pa == 0)
      panic("loadseg: address should exist");
    if(sz - i < PGSIZE)
      n = sz - i;
    else
      n = PGSIZE;
    if(readi(ip, 0, (uint32)pa, offset+i, n) != n)
      return -1;
  }
  
  return 0;
}
