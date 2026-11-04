from msgpack import Encoder, parse


def main() raises:
    var e = Encoder()
    e.map(2)
    e.str("name"); e.str("héllo")
    e.str("when"); e.timestamp(1700000000, 5)
    var d = parse(e.buf)  # str and bin are views into e.buf: e must outlive d
    print(len(d.nodes), d.str(2), d.timestamp(4)[0])
    _ = len(e.buf)
