defmodule JustBash.Commands.Date do
  @moduledoc """
  The `date` command — display the current date and time.

  Output is always UTC. Supported directives:

    * compound — `%F` (`%Y-%m-%d`), `%T` (`%H:%M:%S`), `%R` (`%H:%M`),
      `%D` (`%m/%d/%y`)
    * date — `%Y`, `%y`, `%C`, `%m`, `%d`, `%e` (space-padded), `%j`,
      `%a`, `%A`, `%b`, `%h`, `%B`, `%u`, `%w`
    * time — `%H`, `%M`, `%S`, `%N`, `%I`, `%p`, `%P`, `%Z`, `%s`
    * literal — `%%`, `%n`, `%t`

  An unrecognized directive is emitted verbatim (`%J` → `%J`), as GNU date does,
  so a caller can tell the difference between "not supported" and a real value.

  Flags: `-d` / `--date=`, `-I[FMT]` / `--iso-8601[=FMT]`, `-u`, and the BSD
  `-j` / `-f` pair.
  """
  @behaviour JustBash.Commands.Command

  alias JustBash.Commands.Command

  @default_format "%a %b %d %H:%M:%S UTC %Y"

  @impl true
  def names, do: ["date"]

  @impl true
  def execute(bash, args, _stdin) do
    case parse_args(args) do
      {:ok, opts} ->
        datetime = opts.datetime || DateTime.utc_now()
        format = opts.format || opts.iso_format || @default_format
        output = format_datetime(datetime, format) <> "\n"
        {Command.ok(output), bash}

      {:error, msg} ->
        {Command.error(msg), bash}
    end
  end

  defp parse_args(args) do
    parse_args(args, %{
      format: nil,
      iso_format: nil,
      datetime: nil,
      input_format: nil,
      no_set: false
    })
  end

  defp parse_args([], opts), do: {:ok, opts}

  # Real date rejects competing output formats rather than picking one.
  defp parse_args(["+" <> _format | _rest], %{iso_format: iso}) when iso != nil do
    {:error, "date: multiple output formats specified\n"}
  end

  defp parse_args(["+" <> format | rest], opts) do
    parse_args(rest, %{opts | format: format})
  end

  defp parse_args(["-I" <> spec | rest], opts), do: put_iso_format(spec, rest, opts)
  defp parse_args(["--iso-8601" | rest], opts), do: put_iso_format("", rest, opts)

  defp parse_args(["--iso-8601=" <> spec | rest], opts), do: put_iso_format(spec, rest, opts)

  defp parse_args(["-d", date_str | rest], opts) do
    case parse_date_string(date_str) do
      {:ok, datetime} -> parse_args(rest, %{opts | datetime: datetime})
      {:error, _} -> {:error, "date: invalid date '#{date_str}'\n"}
    end
  end

  defp parse_args(["--date=" <> date_str | rest], opts) do
    case parse_date_string(date_str) do
      {:ok, datetime} -> parse_args(rest, %{opts | datetime: datetime})
      {:error, _} -> {:error, "date: invalid date '#{date_str}'\n"}
    end
  end

  # BSD date: -j flag means "don't set the date" (just display)
  defp parse_args(["-j" | rest], opts) do
    parse_args(rest, %{opts | no_set: true})
  end

  # BSD date: -f input_format to parse a date string
  defp parse_args(["-f", input_format | rest], opts) do
    parse_args(rest, %{opts | input_format: input_format})
  end

  defp parse_args(["-u" | rest], opts) do
    parse_args(rest, opts)
  end

  # When we have an input_format set (BSD -f flag) and encounter a non-option arg
  defp parse_args([<<c, _::binary>> = date_str | rest], %{input_format: input_format} = opts)
       when input_format != nil and c != ?+ and c != ?- do
    case parse_formatted_date(date_str, input_format) do
      {:ok, datetime} ->
        parse_args(rest, %{opts | datetime: datetime, input_format: nil})

      {:error, _} ->
        {:error, "date: invalid date '#{date_str}'\n"}
    end
  end

  defp parse_args([_arg | rest], opts) do
    parse_args(rest, opts)
  end

  defp put_iso_format(_spec, _rest, %{format: format}) when format != nil do
    {:error, "date: multiple output formats specified\n"}
  end

  defp put_iso_format(spec, rest, opts) do
    case iso_format(spec) do
      {:ok, format} -> parse_args(rest, %{opts | iso_format: format})
      :error -> {:error, "date: invalid argument '#{spec}' for '--iso-8601'\n"}
    end
  end

  defp iso_format(spec) when spec in ["", "date"], do: {:ok, "%Y-%m-%d"}
  defp iso_format("hours"), do: {:ok, "%Y-%m-%dT%H+00:00"}
  defp iso_format("minutes"), do: {:ok, "%Y-%m-%dT%H:%M+00:00"}
  defp iso_format("seconds"), do: {:ok, "%Y-%m-%dT%H:%M:%S+00:00"}
  defp iso_format("ns"), do: {:ok, "%Y-%m-%dT%H:%M:%S,%N+00:00"}
  defp iso_format(_spec), do: :error

  defp parse_formatted_date(date_str, format) do
    cond do
      format == "%Y-%m-%d %H:%M:%S" -> parse_space_datetime(date_str)
      format == "%Y-%m-%d" -> parse_date_only(date_str)
      format == "%Y-%m-%dT%H:%M:%S" -> parse_iso_datetime(date_str)
      true -> parse_date_string(date_str)
    end
  end

  defp parse_date_string(str) do
    cond do
      str =~ ~r/^\d{4}-\d{2}-\d{2}$/ -> parse_date_only(str)
      str =~ ~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/ -> parse_iso_datetime(str)
      str =~ ~r/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/ -> parse_space_datetime(str)
      true -> parse_relative_date(str)
    end
  end

  defp parse_date_only(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> {:ok, DateTime.new!(date, ~T[00:00:00], "Etc/UTC")}
      error -> error
    end
  end

  defp parse_iso_datetime(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> {:ok, dt}
      _ -> {:error, :invalid_format}
    end
  end

  defp parse_space_datetime(str) do
    iso_str = String.replace(str, " ", "T") <> "Z"

    case DateTime.from_iso8601(iso_str) do
      {:ok, dt, _offset} -> {:ok, dt}
      _ -> {:error, :invalid_format}
    end
  end

  defp parse_relative_date("now"), do: {:ok, DateTime.utc_now()}

  defp parse_relative_date("yesterday"),
    do: {:ok, DateTime.utc_now() |> DateTime.add(-86_400, :second)}

  defp parse_relative_date("tomorrow"),
    do: {:ok, DateTime.utc_now() |> DateTime.add(86_400, :second)}

  defp parse_relative_date(_), do: {:error, :invalid_format}

  # A single left-to-right scan consumes each directive exactly once, so `%%`
  # escaping works — chained String.replace/3 cannot express it (`%%Y` became
  # `%2024`). Unknown directives pass through verbatim (`%J` -> `%J`), matching
  # GNU date. The scan is byte-wise, not codepoint-wise: format strings are raw
  # binaries and need not be valid UTF-8; every known directive is ASCII, and
  # passthrough reconstructs other bytes verbatim either way.
  defp format_datetime(datetime, format), do: scan(format, datetime, [])

  defp scan(<<>>, _datetime, acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  # A trailing bare `%` is literal, as in real date.
  defp scan(<<?%>>, datetime, acc), do: scan(<<>>, datetime, ["%" | acc])

  defp scan(<<?%, directive, rest::binary>>, datetime, acc) do
    scan(rest, datetime, [directive(directive, datetime) | acc])
  end

  defp scan(<<char, rest::binary>>, datetime, acc) do
    scan(rest, datetime, [<<char>> | acc])
  end

  # Compound directives are composed from their single-field parts so the two
  # can't drift.
  defp directive(?F, dt), do: "#{directive(?Y, dt)}-#{directive(?m, dt)}-#{directive(?d, dt)}"
  defp directive(?T, dt), do: "#{directive(?H, dt)}:#{directive(?M, dt)}:#{directive(?S, dt)}"
  defp directive(?R, dt), do: "#{directive(?H, dt)}:#{directive(?M, dt)}"
  defp directive(?D, dt), do: "#{directive(?m, dt)}/#{directive(?d, dt)}/#{directive(?y, dt)}"

  defp directive(?Y, dt), do: dt.year |> Integer.to_string() |> String.pad_leading(4, "0")
  defp directive(?m, dt), do: pad2(dt.month)
  defp directive(?d, dt), do: pad2(dt.day)
  defp directive(?H, dt), do: pad2(dt.hour)
  defp directive(?M, dt), do: pad2(dt.minute)
  defp directive(?S, dt), do: pad2(dt.second)
  defp directive(?y, dt), do: dt.year |> rem(100) |> pad2()
  defp directive(?C, dt), do: dt.year |> div(100) |> pad2()
  # `%e` is space-padded rather than zero-padded — the one directive where the
  # difference is visible in column-aligned output.
  defp directive(?e, dt), do: dt.day |> Integer.to_string() |> String.pad_leading(2, " ")
  defp directive(?I, dt), do: dt.hour |> twelve_hour() |> pad2()
  defp directive(?p, dt), do: if(dt.hour < 12, do: "AM", else: "PM")
  defp directive(?P, dt), do: dt |> directive(?p) |> String.downcase()
  defp directive(?Z, dt), do: dt.zone_abbr

  defp directive(?N, dt) do
    {microsecond, _precision} = dt.microsecond
    (microsecond * 1_000) |> Integer.to_string() |> String.pad_leading(9, "0")
  end

  defp directive(?s, dt), do: Integer.to_string(DateTime.to_unix(dt))
  defp directive(?a, dt), do: short_day_name(dt)
  defp directive(?A, dt), do: full_day_name(dt)
  defp directive(?b, dt), do: short_month_name(dt)
  defp directive(?h, dt), do: short_month_name(dt)
  defp directive(?B, dt), do: full_month_name(dt)
  defp directive(?j, dt), do: day_of_year(dt)
  defp directive(?u, dt), do: Integer.to_string(Date.day_of_week(dt))
  defp directive(?w, dt), do: Integer.to_string(rem(Date.day_of_week(dt), 7))
  defp directive(?n, _dt), do: "\n"
  defp directive(?t, _dt), do: "\t"
  defp directive(?%, _dt), do: "%"
  defp directive(other, _dt), do: <<?%, other>>

  defp pad2(n), do: n |> Integer.to_string() |> String.pad_leading(2, "0")

  defp twelve_hour(0), do: 12
  defp twelve_hour(hour) when hour > 12, do: hour - 12
  defp twelve_hour(hour), do: hour

  defp short_day_name(dt) do
    case Date.day_of_week(dt) do
      1 -> "Mon"
      2 -> "Tue"
      3 -> "Wed"
      4 -> "Thu"
      5 -> "Fri"
      6 -> "Sat"
      7 -> "Sun"
    end
  end

  defp full_day_name(dt) do
    case Date.day_of_week(dt) do
      1 -> "Monday"
      2 -> "Tuesday"
      3 -> "Wednesday"
      4 -> "Thursday"
      5 -> "Friday"
      6 -> "Saturday"
      7 -> "Sunday"
    end
  end

  defp short_month_name(dt) do
    Enum.at(
      ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec),
      dt.month - 1
    )
  end

  defp full_month_name(dt) do
    Enum.at(
      ~w(January February March April May June July August September October November December),
      dt.month - 1
    )
  end

  defp day_of_year(dt) do
    Date.day_of_year(dt) |> Integer.to_string() |> String.pad_leading(3, "0")
  end
end
