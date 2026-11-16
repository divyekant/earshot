import sys, glob, collections
def rows(pat):
    out={}
    for f in sorted(glob.glob(pat)):
        lines=open(f).read().splitlines()
        h=lines[0].split("\t")
        for l in lines[1:]:
            if not l.strip(): continue
            c=l.split("\t"); c+=[""]*(len(h)-len(c)); out[c[0]]=dict(zip(h,c))
    return out
a=rows(sys.argv[1]); b=rows(sys.argv[2]); col=sys.argv[3]
ids=sorted(set(a)&set(b))
agree=sum(a[i][col]==b[i][col] for i in ids)
conf=collections.Counter((a[i][col],b[i][col]) for i in ids)
print(f"{len(ids)} common, agree {agree} ({agree/len(ids):.3f}); only A {len(set(a)-set(b))}, only B {len(set(b)-set(a))}")
for k,v in sorted(conf.items()): print(" ",k,v)
if col=="need":
    req=lambda x:x in("list","now")
    print(" request agree", sum(req(a[i][col])==req(b[i][col]) for i in ids))
