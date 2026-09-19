import random

def check_template(name, matrix_mask):
    # matrix_mask is 3 rows x 9 cols (0 or 1)
    row_sums = [sum(row) for row in matrix_mask]
    col_sums = [sum(matrix_mask[r][c] for r in range(3)) for c in range(9)]
    total = sum(row_sums)
    
    is_valid = True
    if row_sums != [5, 5, 5]:
        print(f"FAILED {name}: row_sums = {row_sums}")
        is_valid = False
    if any(c < 1 or c > 3 for c in col_sums):
        print(f"FAILED {name}: col_sums = {col_sums}")
        is_valid = False
    if total != 15:
        print(f"FAILED {name}: total = {total}")
        is_valid = False
    if is_valid:
        print(f"PASSED {name}: rows={row_sums}, cols={col_sums}")
    return is_valid

# Template 1
t1 = [
    [1, 0, 1, 0, 1, 0, 1, 0, 1],
    [0, 1, 0, 1, 0, 1, 0, 1, 1],
    [1, 0, 1, 0, 1, 1, 0, 1, 0]
]
check_template("Template 1", t1)

# Template 2
t2 = [
    [1, 1, 0, 1, 0, 1, 0, 1, 0],
    [0, 1, 1, 0, 1, 0, 1, 1, 0],
    [1, 0, 0, 1, 1, 1, 0, 0, 1]
]
check_template("Template 2", t2)

# Template 3
t3 = [
    [1, 0, 1, 1, 0, 1, 0, 1, 0],
    [1, 1, 0, 0, 0, 1, 1, 0, 1],
    [0, 1, 1, 0, 1, 0, 1, 0, 1]
]
check_template("Template 3", t3)

# Template 4
t4 = [
    [1, 1, 0, 0, 1, 1, 0, 1, 0],
    [1, 0, 1, 1, 0, 0, 1, 1, 0],
    [0, 1, 0, 1, 1, 0, 1, 0, 1]
]
check_template("Template 4", t4)

# Template 5
t5 = [
    [0, 1, 0, 1, 0, 1, 1, 0, 1],
    [1, 0, 1, 1, 0, 0, 0, 1, 1],
    [0, 1, 1, 0, 1, 1, 0, 1, 0]
]
check_template("Template 5", t5)

# Template 6
t6 = [
    [1, 0, 1, 1, 0, 0, 1, 1, 0],
    [0, 1, 0, 1, 1, 0, 1, 0, 1],
    [1, 1, 0, 0, 1, 1, 0, 1, 0]
]
check_template("Template 6", t6)

# Template 7
t7 = [
    [1, 0, 1, 0, 1, 1, 0, 0, 1],
    [0, 1, 0, 1, 0, 1, 1, 0, 1],
    [1, 0, 1, 1, 0, 0, 1, 1, 0]
]
check_template("Template 7", t7)

# Template 8
t8 = [
    [0, 1, 0, 1, 1, 0, 1, 1, 0],
    [1, 1, 0, 0, 1, 1, 0, 0, 1],
    [1, 0, 1, 1, 0, 1, 0, 1, 0]
]
check_template("Template 8", t8)
