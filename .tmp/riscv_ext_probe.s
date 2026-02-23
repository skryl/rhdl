.option norvc
.text
.global _start
_start:
  pack a0,a1,a2
  packh a0,a1,a2
  rev8 a0,a1
  clmul a0,a1,a2
  clmulh a0,a1,a2
  clmulr a0,a1,a2
  wrs.nto
  wrs.sto
  prefetch.i 0(a0)
  prefetch.r 0(a0)
  prefetch.w 0(a0)
  cbo.inval 0(a0)
  cbo.clean 0(a0)
  cbo.flush 0(a0)
  cbo.zero 0(a0)
