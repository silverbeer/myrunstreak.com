"""Split data model for per-mile/per-km pace tracking."""

from pydantic import BaseModel, Field


class Split(BaseModel):
    """
    Represents a single split (mile or kilometer) from a run.

    Stores cumulative metrics as returned by SmashRun API.
    Per-split incremental metrics are calculated in database views.
    """

    split_number: int | None = Field(
        default=None,
        description="Sequential split number (1, 2, 3, etc.) - set when storing in DB",
        ge=1,
    )
    split_unit: str | None = Field(
        default=None,
        description="Unit of measurement: 'mi' for miles, 'km' for kilometers - set when storing in DB",
        pattern="^(mi|km)$",
    )

    # Cumulative metrics (as returned by API)
    cumulative_distance: float = Field(
        description="Distance at end of this split (miles or km depending on unit)",
        gt=0,
        alias="distance",
    )
    cumulative_seconds: float = Field(
        description="Time elapsed at end of this split (seconds)",
        gt=0,
        alias="seconds",
    )

    # Performance metrics at this split
    speed_kph: float | None = Field(
        default=None,
        description="Speed at this point (km/h)",
        alias="speed",
        gt=0,
    )
    heart_rate: int | None = Field(
        default=None,
        description="Heart rate at this point (beats per minute)",
        alias="heartRate",
        ge=0,
    )

    # Elevation changes
    cumulative_elevation_gain_meters: float | None = Field(
        default=None,
        description="Total elevation gained from start to this split (meters)",
        alias="elevationGain",
        ge=0,
    )
    cumulative_elevation_loss_meters: float | None = Field(
        default=None,
        description="Total elevation lost from start to this split (meters)",
        alias="elevationLoss",
        ge=0,
    )

    model_config = {"populate_by_name": True}
