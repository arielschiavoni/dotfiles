function check_fonts --description 'Prints out the list of default fonts'
    for family in serif sans-serif monospace
        echo -n "$family: "
        fc-match $family
    end
end
