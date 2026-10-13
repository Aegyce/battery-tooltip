import pathlib, struct, urllib.request, sys

path = pathlib.Path(sys.argv[1])
data = path.read_bytes()
pe = struct.unpack_from('<I', data, 0x3c)[0]
count = struct.unpack_from('<H', data, pe + 6)[0]
opt_size = struct.unpack_from('<H', data, pe + 20)[0]
optional = pe + 24
directory = optional + (112 if struct.unpack_from('<H', data, optional)[0] == 0x20b else 96)
sections = []
for i in range(count):
    pos = optional + opt_size + i * 40
    vs, va, size, raw = struct.unpack_from('<IIII', data, pos + 8)
    sections.append((va, max(vs, size), raw))
def offset(rva):
    for va, size, raw in sections:
        if va <= rva < va + size:
            return raw + rva - va
    raise ValueError(hex(rva))
debug_rva, debug_size = struct.unpack_from('<II', data, directory + 6 * 8)
for pos in range(offset(debug_rva), offset(debug_rva) + debug_size, 28):
    kind, size, rva, raw = struct.unpack_from('<IIII', data, pos + 12)
    if kind != 2 or data[raw:raw + 4] != b'RSDS':
        continue
    import uuid
    guid = uuid.UUID(bytes_le=data[raw + 4:raw + 20]).hex.upper()
    age = struct.unpack_from('<I', data, raw + 20)[0]
    name = data[raw + 24:raw + size].split(b'\0')[0].decode().split('\\')[-1]
    url = f'https://msdl.microsoft.com/download/symbols/{name}/{guid}{age:X}/{name}'
    out = pathlib.Path(sys.argv[2]) / name
    out.parent.mkdir(parents=True, exist_ok=True)
    print(url, flush=True)
    if not out.exists():
        urllib.request.urlretrieve(url, out)
    print(out, out.stat().st_size)
