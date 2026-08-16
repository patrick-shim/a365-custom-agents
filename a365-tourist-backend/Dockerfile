# MCR does not publish the repository's Visual Studio-serviced 10.0.110 SDK.
# Keep the container toolchain independently reproducible on a published SDK.
FROM mcr.microsoft.com/dotnet/sdk:10.0.302 AS build
WORKDIR /src

COPY Directory.Build.props Directory.Packages.props ./
COPY server/agent/SeoulTourist.Agent/SeoulTourist.Agent.csproj server/agent/SeoulTourist.Agent/
COPY server/agent-host/SeoulTourist.AgentHost/SeoulTourist.AgentHost.csproj server/agent-host/SeoulTourist.AgentHost/

RUN dotnet restore server/agent-host/SeoulTourist.AgentHost/SeoulTourist.AgentHost.csproj

COPY server/agent/SeoulTourist.Agent/ server/agent/SeoulTourist.Agent/
COPY server/agent-host/SeoulTourist.AgentHost/ server/agent-host/SeoulTourist.AgentHost/

RUN dotnet publish server/agent-host/SeoulTourist.AgentHost/SeoulTourist.AgentHost.csproj \
    --configuration Release \
    --no-restore \
    --output /app/publish \
    /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app

ENV ASPNETCORE_URLS=http://+:8080 \
    ASPNETCORE_ENVIRONMENT=Production \
    DOTNET_EnableDiagnostics=0

EXPOSE 8080

COPY --from=build /app/publish .

USER $APP_UID
ENTRYPOINT ["dotnet", "SeoulTourist.AgentHost.dll"]
