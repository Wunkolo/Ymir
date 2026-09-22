#pragma once

#include <util/service_locator.hpp>

#include "midi_types.hpp"

#include <atomic>
#include <functional>
#include <memory>
#include <mutex>
#include <string>

namespace app::services {

/// @brief Provides access to real-time MIDI inputs and outputs through RtMidi.
class MIDIService {
public:
    MIDIService(util::ServiceLocator &serviceLocator);
    ~MIDIService();

    void Initialize(std::function<void()> onComplete);

    std::string GetMidiVirtualInputPortName() const;
    std::string GetMidiVirtualOutputPortName() const;

    std::string GetMidiInputPortName() const;
    std::string GetMidiOutputPortName() const;

    int FindInputPortByName(std::string name) const;
    int FindOutputPortByName(std::string name) const;

    std::shared_ptr<util::IRtMidiIn> GetInput() const {
        return m_input.load(std::memory_order_acquire);
    }
    std::shared_ptr<util::IRtMidiOut> GetOutput() const {
        return m_output.load(std::memory_order_acquire);
    }

    void SetMidiInputCallback(RtMidiIn::RtMidiCallback callback, void *userData = nullptr);

private:
    util::ServiceLocator &m_serviceLocator;

    std::atomic<std::shared_ptr<util::IRtMidiIn>> m_input;
    std::atomic<std::shared_ptr<util::IRtMidiOut>> m_output;

    std::mutex m_mtxCallback;
    RtMidiIn::RtMidiCallback m_inputCallback;
    void *m_inputCallbackUserData;
};

} // namespace app::services
