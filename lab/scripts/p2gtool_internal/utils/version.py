from functools import total_ordering


@total_ordering
class Version:
    def __init__(self, major, minor):
        assert isinstance(major, int)
        assert isinstance(minor, int)
        self.major = major
        self.minor = minor

    @classmethod
    def from_string(cls, s):
        try:
            return cls(*list(map(int, s.split(".")[:2])))
        except (AttributeError, ValueError, TypeError) as e:
            raise VersionParseError(
                e, f"Expected string on form DIGITS DOT DIGITS, got: {s}"
            )

    @classmethod
    def from_string_or_null(cls, s):
        try:
            return cls.from_string(s)
        except VersionParseError:
            return NullVersion()

    @classmethod
    def from_string_create_minor(cls, s):
        if "." not in s:
            s = s + ".0"
        return cls.from_string(s)

    def __str__(self):
        if self.minor == 0:
            return str(self.major)
        else:
            return str(self.major) + "." + str(self.minor)

    def __repr__(self):
        return "<Version {}.{}>".format(self.major, self.minor)

    def __eq__(self, other):
        return self.major == other.major and self.minor == other.minor

    def __ne__(self, other):
        return self.major != other.major or self.minor != other.minor

    def __lt__(self, other):
        return self.major <= other.major and self.minor < other.minor

