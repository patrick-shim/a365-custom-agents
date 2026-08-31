# MCR does not publish the repository's Visual Studio-serviced 10.0.110 SDK.
# Keep the container toolchain independently reproducible on a published SDK.
FROM mcr.microsoft.com/dotnet/sdk:10.0.302 AS build
WORKDIR /src

COPY Directory.Build.props Directory.Packages.props ./
COPY server/agent/KoreaExpert.Agent/KoreaExpert.Agent.csproj server/agent/KoreaExpert.Agent/
COPY server/agent-host/KoreaExpert.AgentHost/KoreaExpert.AgentHost.csproj server/agent-host/KoreaExpert.AgentHost/

RUN dotnet restore server/agent-host/KoreaExpert.AgentHost/KoreaExpert.AgentHost.csproj

COPY server/agent/KoreaExpert.Agent/ server/agent/KoreaExpert.Agent/
COPY server/agent-host/KoreaExpert.AgentHost/ server/agent-host/KoreaExpert.AgentHost/

RUN dotnet publish server/agent-host/KoreaExpert.AgentHost/KoreaExpert.AgentHost.csproj \
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
ENTRYPOINT ["dotnet", "KoreaExpert.AgentHost.dll"]
