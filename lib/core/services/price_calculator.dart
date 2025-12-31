class PriceCalculator {
  // PS4 pricing per hour
  static const double ps4HourlyRate = 250.0;

  // PS5 pricing per hour
  static const double ps5HourlyRate = 350.0;

  // Additional controller charge per controller (flat rate)
  static const double additionalControllerRate = 150.0;

  // Calculate price based on hours and minutes for PS4
  static double ps4Price({
    required int hours,
    required int minutes,
    int additionalControllers = 0,
  }) {
    double totalHours = hours + (minutes / 60.0);
    // Round up to nearest 15 minutes
    totalHours = (totalHours * 4).ceil() / 4.0;
    double basePrice = totalHours * ps4HourlyRate;
    // Add additional controller charges: Rs 150 per controller (flat rate)
    if (additionalControllers > 0) {
      basePrice += (additionalControllers * additionalControllerRate);
    }
    return basePrice;
  }

  // Calculate price based on hours and minutes for PS5
  static double ps5Price({
    required int hours,
    required int minutes,
    int additionalControllers = 0,
  }) {
    double totalHours = hours + (minutes / 60.0);
    // Round up to nearest 15 minutes
    totalHours = (totalHours * 4).ceil() / 4.0;
    double basePrice = totalHours * ps5HourlyRate;
    // Add additional controller charges: Rs 150 per controller (flat rate)
    if (additionalControllers > 0) {
      basePrice += (additionalControllers * additionalControllerRate);
    }
    return basePrice;
  }

  static int carSimulator() => 500;

  static int vr() => 700;

  static int theatre({required int hours, required int people}) {
    int base = switch (hours) {
      1 => 1500,
      2 => 2000,
      3 => 2500,
      _ => 0,
    };

    if (people > 4) {
      base += (people - 4) * 350;
    }

    return base;
  }
}
