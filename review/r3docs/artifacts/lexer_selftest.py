import sys
sys.path.insert(0, "/home/winny/.hermes/profiles/qwen-executor/cache/scratch/r3docs")
from token_cmp import strip_keep_tokens

path = "/home/winny/curve-gauge-lister/test/fork/ForkFixture.sol"
t = strip_keep_tokens(open(path).read())
strs = [x for x in t if x.startswith('"')]
print("string tokens kept:", len(strs))
print(strs[:3])
leak = [x for x in t if "CX-FORK-TRACE" in x or "@dev" in x]
print("comment leak:", leak[:3])

src = (
    'a /* "not a string */ b;\n'
    '// "also not\n'
    'c;\n'
    'string s = "has // inside /* and */";\n'
)
print("adversarial:", strip_keep_tokens(src))
