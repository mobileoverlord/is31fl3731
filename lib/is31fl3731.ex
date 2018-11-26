defmodule IS31FL3731 do
  use GenServer

  alias Circuits.I2C

  @address 0x75
  @bus "i2c-1"

  @gamma [
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2,
    2, 2, 2, 3, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5,
    6, 6, 6, 7, 7, 7, 8, 8, 8, 9, 9, 9, 10, 10, 11, 11,
    11, 12, 12, 13, 13, 13, 14, 14, 15, 15, 16, 16, 17, 17, 18, 18,
    19, 19, 20, 21, 21, 22, 22, 23, 23, 24, 25, 25, 26, 27, 27, 28,
    29, 29, 30, 31, 31, 32, 33, 34, 34, 35, 36, 37, 37, 38, 39, 40,
    40, 41, 42, 43, 44, 45, 46, 46, 47, 48, 49, 50, 51, 52, 53, 54,
    55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70,
    71, 72, 73, 74, 76, 77, 78, 79, 80, 81, 83, 84, 85, 86, 88, 89,
    90, 91, 93, 94, 95, 96, 98, 99, 100, 102, 103, 104, 106, 107, 109, 110,
    111, 113, 114, 116, 117, 119, 120, 121, 123, 124, 126, 128, 129, 131, 132, 134,
    135, 137, 138, 140, 142, 143, 145, 146, 148, 150, 151, 153, 155, 157, 158, 160,
    162, 163, 165, 167, 169, 170, 172, 174, 176, 178, 179, 181, 183, 185, 187, 189,
    191, 193, 194, 196, 198, 200, 202, 204, 206, 208, 210, 212, 214, 216, 218, 220,
    222, 224, 227, 229, 231, 233, 235, 237, 239, 241, 244, 246, 248, 250, 252, 255]

  @mode_register 0x00
  @frame_register 0x01
  @autoplay1_register 0x02
  @autoplay2_register 0x03
  # @blink_register 0x05
  @audiosync_register 0x06
  # @breath1_register 0x08
  # @breath2_register 0x09
  @shutdown_register 0x0a
  # @gain_register 0x0b
  # @adc_register 0x0c

  @config_bank 0x0b
  @bank_address 0xfd

  @picture_mode 0x00
  @autoplay_mode 0x08
  @audioplay_mode 0x18

  @modes [:picture, :autoplay, :audioplay]

  @modes_values [
    picture: @picture_mode,
    autoplay: @autoplay_mode,
    audioplay: @audioplay_mode
  ]

  @enable_offset 0x00
  @blink_offset 0x12
  @pwm_offset 0x24

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  # Command registers

  def page(pid, :config) do
    GenServer.call(pid, {:write, <<@bank_address, @config_bank>>})
  end

  def page(pid, page) do
    GenServer.call(pid, {:write, <<@bank_address, page>>})
  end

  # Frame registers

  def led_control(pid, binary) when is_binary(binary) do
    GenServer.call(pid, {:write, <<@enable_offset, binary :: binary>>})
  end

  def blink_control(pid, binary) when is_binary(binary) do
    GenServer.call(pid, {:write, <<@blink_offset, binary :: binary>>})
  end

  def pwm_control(pid, binary) when is_binary(binary) do
    :binary.bin_to_list(binary)
    |> Enum.map(&gamma/1)
    |> Enum.chunk_every(32)
    |> Enum.reduce(0, fn(chunk, offset) ->

      chunk = :binary.list_to_bin(chunk)
      GenServer.call(pid, {:write, <<@pwm_offset + offset, chunk :: binary>>})
      offset + 32
    end)
  end

  # Function registers

  def mode(pid, mode) when mode in @modes do
    mode_value = Keyword.get(@modes_values, mode)
    GenServer.call(pid, {:write, <<@mode_register, mode_value>>})
  end

  def mode(_pid, _mode) do
    {:error, "Mode must be one of #{inspect @modes}"}
  end

  def frame(pid, frame) when frame >=0 and frame < 7 do
    GenServer.call(pid, {:write, <<@frame_register, frame>>})
  end

  def frame(_pid, _frame) do
    {:error, "Frame must be in range 0..7"}
  end

  def autoplay1(pid, loops, frames) do
    GenServer.call(pid, {:write, <<
      @autoplay1_register,
      0 :: size(1),
      loops :: size(3),
      0 :: size(1),
      frames :: size(3)
    >>})
  end

  def autoplay2(pid, loops, frames) do
    GenServer.call(pid, {:write, <<
      @autoplay2_register,
      0 :: size(1),
      loops :: size(3),
      0 :: size(1),
      frames :: size(3)
    >>})
  end

  def audiosync(pid, bool) when is_boolean(bool) do
    value = if bool, do: 1, else: 0
    GenServer.call(pid, {:write, <<@audiosync_register, value>>})
  end

  def shutdown(pid, bool) when is_boolean(bool) do
    value = if bool, do: 0, else: 1
    GenServer.call(pid, {:write, <<@shutdown_register, value>>})
  end

  # Other funs

  def reset(pid) do
    page(pid, :config)
    shutdown(pid, true)
    :timer.sleep(1)
    shutdown(pid, false)
  end

  def raw_write(pid, data) do
    GenServer.call(pid, {:write, data})
  end

  # GenServer callbacks

  def init(opts) do
    address = opts[:address] || @address
    bus = opts[:bus] || @bus
    {:ok, bus} = I2C.open(bus)

    {:ok, %{
      bus: bus,
      address: address
    }}
  end

  def handle_call({:write, data}, _from, s) do
    {:reply, write(data, s), s}
  end

  defp write(data, %{bus: bus, address: address}) do
    I2C.write(bus, address, data)
  end

  defp gamma(index), do: Enum.at(@gamma, index)

end
