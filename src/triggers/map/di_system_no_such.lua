-- "There doesn't seem to be a star system with that name!" - the answer to a
-- "di system X" for something that is not a star system at all (a planet, a
-- typo). Worth more than the planet list we asked for: it stops a system
-- sweep before it walks to a link room and jumps at a name that cannot exist.
if f2t_map_di_system_no_such_system then
    f2t_map_di_system_no_such_system()
end
