def get_float_input(prompt):
    while True:
        try:
            val = float(input(prompt))
            if val <= 0:
                print("Value must be greater than zero.")
                continue
            return val
        except ValueError:
            print("Invalid input. Please enter a numerical value.")

def main():
    print("=== Car Speed Calculator ===")
    
    # Get distance unit
    print("\nSelect distance unit:")
    print("1. Kilometers (km)")
    print("2. Miles (mi)")
    print("3. Meters (m)")
    dist_choice = input("Enter choice (1-3) [default: 1]: ").strip() or "1"
    
    # Get distance value
    distance = get_float_input("Enter the distance traveled: ")
    
    # Get time unit
    print("\nSelect time unit:")
    print("1. Hours (h)")
    print("2. Minutes (min)")
    print("3. Seconds (s)")
    time_choice = input("Enter choice (1-3) [default: 1]: ").strip() or "1"
    
    # Get time value
    time = get_float_input("Enter the time taken: ")
    
    # Convert distance to meters
    # 1 km = 1000 m
    # 1 mi = 1609.344 m
    if dist_choice == "1":
        dist_m = distance * 1000.0
        dist_unit_str = "km"
    elif dist_choice == "2":
        dist_m = distance * 1609.344
        dist_unit_str = "miles"
    elif dist_choice == "3":
        dist_m = distance
        dist_unit_str = "meters"
    else:
        print("Invalid distance choice. Defaulting to Kilometers.")
        dist_m = distance * 1000.0
        dist_unit_str = "km"
        
    # Convert time to seconds
    # 1 hr = 3600 s
    # 1 min = 60 s
    if time_choice == "1":
        time_s = time * 3600.0
        time_unit_str = "hours"
    elif time_choice == "2":
        time_s = time * 60.0
        time_unit_str = "minutes"
    elif time_choice == "3":
        time_s = time
        time_unit_str = "seconds"
    else:
        print("Invalid time choice. Defaulting to Hours.")
        time_s = time * 3600.0
        time_unit_str = "hours"
        
    # Calculate speed in m/s
    speed_mps = dist_m / time_s
    
    # Convert speed to other units
    # 1 m/s = 3.6 km/h
    # 1 m/s = 2.236936 mph
    speed_kmh = speed_mps * 3.6
    speed_mph = speed_mps * 2.236936
    
    print("\n" + "="*30)
    print("           RESULTS            ")
    print("="*30)
    print(f"Distance: {distance:.2f} {dist_unit_str}")
    print(f"Time:     {time:.2f} {time_unit_str}")
    print("-" * 30)
    print(f"Speed:    {speed_kmh:.2f} km/h")
    print(f"Speed:    {speed_mph:.2f} mph")
    print(f"Speed:    {speed_mps:.2f} m/s")
    print("="*30)

if __name__ == "__main__":
    main()
