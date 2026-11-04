// skyHAB Project <src@lispm.net>
// Copyright (c) 2026 I. Finder
// SPDX-License-Identifier: MIT

#include "skylab/ephemeris.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <ctime>
#include <iomanip>
#include <sstream>
#include <utility>

namespace skylab {
namespace {
constexpr double pi = 3.14159265358979323846;
double radians(double degrees) { return degrees * pi / 180.0; }
double degrees(double radians_value) { return radians_value * 180.0 / pi; }
std::int64_t now_ms() { return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::system_clock::now().time_since_epoch()).count(); }
Observation value(const nlohmann::json& device, std::string metric, nlohmann::json datum, std::string unit = {}) {
  return {device.value("id", "site-sun"), std::move(metric), std::move(datum), std::move(unit), "good", now_ms()};
}
std::string local_clock(std::time_t instant) {
  std::tm local{}; localtime_r(&instant, &local); std::ostringstream out;
  out << std::put_time(&local, "%l:%M %p"); auto text = out.str();
  if (!text.empty() && text.front() == ' ') text.erase(text.begin()); return text;
}
}

PollResult poll_ephemeris(const nlohmann::json& device) {
  try {
    const auto config = device.value("config", nlohmann::json::object());
    const double latitude = config.at("latitude").get<double>();
    const double longitude = config.at("longitude").get<double>();
    const std::string site_address = config.value("address", device.value("location", ""));
    std::ostringstream coordinate_text;
    coordinate_text << std::fixed << std::setprecision(5) << std::abs(latitude) << "° " << (latitude >= 0 ? "N" : "S")
                    << " · " << std::abs(longitude) << "° " << (longitude >= 0 ? "E" : "W");
    const auto now = std::time(nullptr); std::tm local{}; localtime_r(&now, &local);
    const int day = local.tm_yday + 1;
    const double gamma = 2.0 * pi / 365.0 * (day - 1);
    const double equation = 229.18 * (0.000075 + 0.001868 * std::cos(gamma) - 0.032077 * std::sin(gamma)
                           - 0.014615 * std::cos(2 * gamma) - 0.040849 * std::sin(2 * gamma));
    const double declination = 0.006918 - 0.399912 * std::cos(gamma) + 0.070257 * std::sin(gamma)
                             - 0.006758 * std::cos(2 * gamma) + 0.000907 * std::sin(2 * gamma)
                             - 0.002697 * std::cos(3 * gamma) + 0.00148 * std::sin(3 * gamma);
    const double solar_noon_utc = 720.0 - 4.0 * longitude - equation;
    auto crossings = [&](double zenith) {
      const double cosine_hour = std::cos(radians(zenith)) / (std::cos(radians(latitude)) * std::cos(declination))
                               - std::tan(radians(latitude)) * std::tan(declination);
      if (cosine_hour < -1.0 || cosine_hour > 1.0) throw std::runtime_error("solar crossing is undefined at this latitude and date");
      const double hour_angle = degrees(std::acos(cosine_hour));
      return std::pair{solar_noon_utc - 4.0 * hour_angle, solar_noon_utc + 4.0 * hour_angle};
    };
    const auto [sunrise_utc, sunset_utc] = crossings(90.833);
    const auto [civil_dawn_utc, civil_dusk_utc] = crossings(96.0);
    const auto [nautical_dawn_utc, nautical_dusk_utc] = crossings(102.0);
    const auto [astronomical_dawn_utc, astronomical_dusk_utc] = crossings(108.0);
    std::tm utc_date{}; utc_date.tm_year = local.tm_year; utc_date.tm_mon = local.tm_mon; utc_date.tm_mday = local.tm_mday;
    const auto utc_midnight = timegm(&utc_date);
    const auto sunrise = utc_midnight + static_cast<std::time_t>(std::llround(sunrise_utc * 60.0));
    const auto sunset = utc_midnight + static_cast<std::time_t>(std::llround(sunset_utc * 60.0));
    auto instant = [&](double utc_minutes) { return utc_midnight + static_cast<std::time_t>(std::llround(utc_minutes * 60.0)); };
    const double progress = std::clamp(100.0 * std::difftime(now, sunrise) / std::difftime(sunset, sunrise), 0.0, 100.0);
    const bool daylight = now >= sunrise && now < sunset;
    const std::string phase = daylight ? "daylight" : (now < sunrise ? "before sunrise" : "after sunset");
    const auto transition = now < sunrise ? std::string("Sunrise ") + local_clock(sunrise)
                                          : now < sunset ? std::string("Sunset ") + local_clock(sunset)
                                                         : std::string("Sunrise tomorrow");
    const double local_minutes = local.tm_hour * 60.0 + local.tm_min + local.tm_sec / 60.0;
    const double offset_minutes = local.tm_gmtoff / 60.0;
    const double true_solar_minutes = std::fmod(local_minutes + equation + 4.0 * longitude - offset_minutes + 1440.0, 1440.0);
    const double current_hour_angle = radians(true_solar_minutes / 4.0 - 180.0);
    const double altitude = degrees(std::asin(std::sin(radians(latitude)) * std::sin(declination)
                          + std::cos(radians(latitude)) * std::cos(declination) * std::cos(current_hour_angle)));
    std::vector<Observation> observations{
      value(device, "health", "responding"), value(device, "site_address", site_address),
      value(device, "site_coordinates", coordinate_text.str()), value(device, "latitude", latitude, "°"), value(device, "longitude", longitude, "°"),
      value(device, "sunrise", local_clock(sunrise)),
      value(device, "sunset", local_clock(sunset)), value(device, "daylight", daylight),
      value(device, "civil_dawn", local_clock(instant(civil_dawn_utc))), value(device, "civil_dusk", local_clock(instant(civil_dusk_utc))),
      value(device, "nautical_dawn", local_clock(instant(nautical_dawn_utc))), value(device, "nautical_dusk", local_clock(instant(nautical_dusk_utc))),
      value(device, "astronomical_dawn", local_clock(instant(astronomical_dawn_utc))), value(device, "astronomical_dusk", local_clock(instant(astronomical_dusk_utc))),
      value(device, "solar_phase", phase), value(device, "solar_progress", progress, "%"),
      value(device, "solar_altitude", altitude, "°"),
      value(device, "daylight_duration", std::difftime(sunset, sunrise), "s"),
      value(device, "day_progress", local_minutes / 14.4, "%"),
      value(device, "sunrise_day_progress", (sunrise_utc + offset_minutes) / 14.4, "%"),
      value(device, "sunset_day_progress", (sunset_utc + offset_minutes) / 14.4, "%"),
      value(device, "civil_dawn_day_progress", (civil_dawn_utc + offset_minutes) / 14.4, "%"),
      value(device, "civil_dusk_day_progress", (civil_dusk_utc + offset_minutes) / 14.4, "%"),
      value(device, "nautical_dawn_day_progress", (nautical_dawn_utc + offset_minutes) / 14.4, "%"),
      value(device, "nautical_dusk_day_progress", (nautical_dusk_utc + offset_minutes) / 14.4, "%"),
      value(device, "astronomical_dawn_day_progress", (astronomical_dawn_utc + offset_minutes) / 14.4, "%"),
      value(device, "astronomical_dusk_day_progress", (astronomical_dusk_utc + offset_minutes) / 14.4, "%"),
      value(device, "next_transition", transition)
    };
    return {"responding", "", std::move(observations)};
  } catch (const std::exception& error) {
    return {"degraded", error.what(), {value(device, "health", "degraded")}};
  }
}
}
