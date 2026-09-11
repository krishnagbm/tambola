import random
import time
import concurrent.futures
from threading import Lock

class PostgreSQLSimulation:
    def __init__(self):
        self.games = {}
        self.registrations = {}
        self.tickets = {} # (game_id, user_id) -> ticket
        self.lock = Lock()
        
    def create_game_with_players(self, game_id, count):
        self.games[game_id] = {"status": "OPEN", "final_capacity": count}
        self.registrations[game_id] = []
        for i in range(count):
            self.registrations[game_id].append({
                "user_id": f"user_{i+1}",
                "registration_seq": i + 1,
                "seat_status": "CONFIRMED"
            })

    def MPT_generate_ticket_matrix(self):
        """Replicates PostgreSQL public.MPT_generate_ticket_matrix()"""
        matrix = [[0]*9 for _ in range(3)]
        for col in range(1, 10):
            v_min = 1 if col == 1 else (col - 1) * 10
            v_max = 90 if col == 9 else (col * 10) - 1
            v_count = 2 if col in [1, 3, 5, 6, 8, 9] else 1
            
            selected = sorted(random.sample(range(v_min, v_max + 1), v_count))
            
            if col == 1:
                matrix[0][0], matrix[2][0] = selected[0], selected[1]
            elif col == 2:
                matrix[1][1] = selected[0]
            elif col == 3:
                matrix[0][2], matrix[2][2] = selected[0], selected[1]
            elif col == 4:
                matrix[1][3] = selected[0]
            elif col == 5:
                matrix[0][4], matrix[2][4] = selected[0], selected[1]
            elif col == 6:
                matrix[1][5], matrix[2][5] = selected[0], selected[1]
            elif col == 7:
                matrix[0][6] = selected[0]
            elif col == 8:
                matrix[1][7], matrix[2][7] = selected[0], selected[1]
            elif col == 9:
                matrix[0][8], matrix[1][8] = selected[0], selected[1]
                
        return matrix

    def MPT_start_game_and_charge(self, game_id, bulk_threshold=300):
        """Replicates PostgreSQL public.MPT_start_game_and_charge()"""
        with self.lock:
            game = self.games[game_id]
            regs = self.registrations[game_id]
            for r in regs:
                r["seat_status"] = "ELIGIBLE"
                
            confirmed_count = len(regs)
            game["status"] = "IN_PROGRESS"
            
            # Threshold-gated bulk generation
            if confirmed_count <= bulk_threshold:
                for r in regs:
                    ticket = self._generate_and_insert_ticket_unsafe(game_id, r["user_id"], r["registration_seq"])
                    
            return {
                "game_id": game_id,
                "status": "IN_PROGRESS",
                "eligible_players": confirmed_count,
                "lazy_ticket_issuance": (confirmed_count > bulk_threshold),
                "bulk_tickets_created": len([t for (g, u), t in self.tickets.items() if g == game_id])
            }

    def MPT_get_or_create_player_ticket(self, game_id, user_id):
        """Replicates PostgreSQL public.MPT_get_or_create_player_ticket()"""
        with self.lock:
            # 1. Idempotency check: if exists, return immediately
            if (game_id, user_id) in self.tickets:
                return self.tickets[(game_id, user_id)]
            
            # 2. Check eligibility
            reg = next((r for r in self.registrations[game_id] if r["user_id"] == user_id and r["seat_status"] == "ELIGIBLE"), None)
            if not reg:
                raise Exception("NOT_ELIGIBLE")
            
            # 3. Generate with retry loop (up to 100 attempts)
            return self._generate_and_insert_ticket_unsafe(game_id, user_id, reg["registration_seq"])

    def _generate_and_insert_ticket_unsafe(self, game_id, user_id, reg_seq):
        existing_matrices = [t["ticket_matrix"] for (g, u), t in self.tickets.items() if g == game_id]
        
        attempts = 0
        while attempts < 100:
            matrix = self.MPT_generate_ticket_matrix()
            if matrix not in existing_matrices:
                ticket = {
                    "game_id": game_id,
                    "user_id": user_id,
                    "ticket_matrix": matrix,
                    "ticket_number": reg_seq
                }
                self.tickets[(game_id, user_id)] = ticket
                return ticket
            attempts += 1
        raise Exception("TICKET_GENERATION_FAILED")


def run_tests():
    print("=== MEGA-EVENT TICKET ISSUANCE VERIFICATION (2a, 2b, 2c) ===")
    pg = PostgreSQLSimulation()
    
    # -------------------------------------------------------------
    # 2a: Multi-user on-demand issuance, uniqueness, seq matching, idempotency
    # -------------------------------------------------------------
    print("\n[TEST 2a] Running MPT_get_or_create_player_ticket Uniqueness & Idempotency Test...")
    game_2a = "game_2a"
    pg.create_game_with_players(game_2a, 25)
    # Start game in lazy mode
    pg.MPT_start_game_and_charge(game_2a, bulk_threshold=0)
    
    seen_matrices = set()
    for i in range(1, 26):
        uid = f"user_{i}"
        t1 = pg.MPT_get_or_create_player_ticket(game_2a, uid)
        
        # Check registration_seq matching
        assert t1["ticket_number"] == i, f"Expected ticket_number={i}, got {t1['ticket_number']}"
        sig1 = str(t1["ticket_matrix"])
        assert sig1 not in seen_matrices, "Duplicate ticket matrix detected in game!"
        seen_matrices.add(sig1)
        
        # Check idempotency (call twice for same user)
        t2 = pg.MPT_get_or_create_player_ticket(game_2a, uid)
        assert t2 == t1, "Idempotency failed: second call returned different ticket!"
        assert t2["ticket_matrix"] == t1["ticket_matrix"]
        
    print(f" -> Passed! Verified {len(seen_matrices)} unique tickets, registration_seq matching, and 100% idempotency.")

    # -------------------------------------------------------------
    # 2b: Threshold-gated bulk vs. lazy simulation
    # -------------------------------------------------------------
    print("\n[TEST 2b] Testing Threshold-gated bulk vs lazy generation...")
    # Scenario B1: Standard 50-player game with threshold 300
    game_b1 = "game_standard_50"
    pg.create_game_with_players(game_b1, 50)
    res_b1 = pg.MPT_start_game_and_charge(game_b1, bulk_threshold=300)
    assert res_b1["lazy_ticket_issuance"] is False
    assert res_b1["bulk_tickets_created"] == 50, "Standard game must eagerly generate all 50 tickets"
    
    # Scenario B2: Mega game (350 players with threshold 300)
    game_b2 = "game_mega_350"
    pg.create_game_with_players(game_b2, 350)
    res_b2 = pg.MPT_start_game_and_charge(game_b2, bulk_threshold=300)
    assert res_b2["lazy_ticket_issuance"] is True
    assert res_b2["bulk_tickets_created"] == 0, "Mega game must create 0 tickets at start (skip bulk loop)"
    
    # Simulate players lazy-generating upon opening ticket screen
    for i in range(1, 101):
        t = pg.MPT_get_or_create_player_ticket(game_b2, f"user_{i}")
        assert t["ticket_number"] == i
    print(" -> Passed! Standard game (50) eagerly generated 50 tickets; Mega game (350) skipped bulk loop (0 at start) and lazy-generated on demand.")

    # -------------------------------------------------------------
    # 2c: High-Concurrency Check (simultaneous multi-threaded requests)
    # -------------------------------------------------------------
    print("\n[TEST 2c] Running High-Concurrency Test (100 parallel client requests)...")
    game_2c = "game_concurrent_100"
    pg.create_game_with_players(game_2c, 100)
    pg.MPT_start_game_and_charge(game_2c, bulk_threshold=0)
    
    def worker(user_idx):
        return pg.MPT_get_or_create_player_ticket(game_2c, f"user_{user_idx}")
        
    start_time = time.perf_counter()
    with concurrent.futures.ThreadPoolExecutor(max_workers=20) as executor:
        results = list(executor.map(worker, range(1, 101)))
        
    elapsed = time.perf_counter() - start_time
    
    signatures = [str(t["ticket_matrix"]) for t in results]
    assert len(set(signatures)) == 100, f"Collision detected under concurrency! Unique={len(set(signatures))}"
    for idx, t in enumerate(results):
        assert t["ticket_number"] == idx + 1
        
    print(f" -> Passed! 100 parallel requests generated in {elapsed:.3f}s with 100 strictly unique tickets and 0 collisions.")
    print("\nALL VERIFICATION TESTS COMPLETED SUCCESSFULLY!")

if __name__ == "__main__":
    run_tests()
