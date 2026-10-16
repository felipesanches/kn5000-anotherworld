import sys
d=open(sys.argv[1],'rb').read()
def u8(p): return d[p]
def u16(p): return (d[p]<<8)|d[p+1]
pc=0
N=len(d)
copies=[]; selects=[]; fills=[]; blits=[]
# linear disassembly following oracle operand consumption
while pc < N:
    op=d[pc]; start=pc; pc+=1
    try:
        if op==0x00: pc+=3
        elif op==0x01: pc+=2
        elif op==0x02: pc+=2
        elif op==0x03: pc+=3
        elif op==0x04: pc+=2
        elif op==0x05: pass
        elif op==0x06: pass
        elif op==0x07: pc+=2
        elif op==0x08: pc+=3
        elif op==0x09: pc+=3
        elif op==0x0A:
            mode=d[pc]; pc+=1; pc+=1 # var idx
            m=mode&0xC0
            if m==0x80: pc+=1
            elif m==0x40: pc+=2
            else: pc+=1
            pc+=2 # target
        elif op==0x0B: pc+=2
        elif op==0x0C: pc+=3
        elif op==0x0D:
            selects.append((start,d[pc])); pc+=1
        elif op==0x0E:
            fills.append((start,d[pc],d[pc+1])); pc+=2
        elif op==0x0F:
            src=d[pc]; dst=d[pc+1]; copies.append((start,src,dst)); pc+=2
        elif op==0x10:
            blits.append((start,d[pc])); pc+=1
        elif op==0x11: pass
        elif op==0x12: pc+=5
        elif op==0x13: pc+=2
        elif op==0x14: pc+=3
        elif op==0x15: pc+=3
        elif op==0x16: pc+=3
        elif op==0x17: pc+=3
        elif op==0x18: pc+=5
        elif op==0x19: pc+=2
        elif op==0x1A: pc+=5
        elif op&0x80:
            pc+=3  # offset hi uses opcode, +1 lo, +1 x, +1 y
        elif op&0x40:
            pc+=2 # offset u16
            xsub=(op>>4)&3
            pc+=1 # x byte
            if xsub==0: pc+=1
            ysub=(op>>2)&3
            pc+=1 # y byte
            if ysub==0: pc+=1
            z=op&3
            if z==1 or z==2: pc+=1
        else:
            # unknown (0x1B..0x3F) -> stop to avoid garbage
            break
    except IndexError:
        break
print("decoded up to pc=%d of %d"%(pc,N))
print("\nCOPY_VIDEO_PAGE (0x0F) src,dst:")
for a,s,t in copies:
    flag80 = "VSCROLL(0x80)" if (s<0xFE and s&0x80) else ""
    pg = ("FRONT(0xFE)" if s==0xFE else "BACK(0xFF)" if s==0xFF else "page %d"%(s&3))
    print("  @0x%04X  src=0x%02X -> %-12s %s   dst=0x%02X"%(a,s,pg,flag80,t))
print("\nSELECT_VIDEO_PAGE (0x0D):", [(hex(a),hex(p)) for a,p in selects])
print("\nFILL_VIDEO_PAGE (0x0E):", [(hex(a),hex(p),c) for a,p,c in fills])
print("\nBLIT (0x10):", [(hex(a),hex(p)) for a,p in blits])
